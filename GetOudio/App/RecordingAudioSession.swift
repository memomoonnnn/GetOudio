import AVFAudio
import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import GetOudioCore

final class RecordingAudioSession {
    enum SessionError: LocalizedError {
        case unavailableAudioUnit
        case invalidInputFormat
        case bufferOverflow

        var errorDescription: String? {
            switch self {
            case .unavailableAudioUnit: return "无法创建音频设备连接"
            case .invalidInputFormat: return "Audio Bridge 没有可用的输入格式"
            case .bufferOverflow: return "录音写入速度跟不上输入信号"
            }
        }
    }

    let sampleRate: Double
    let channelCount: Int

    private let inputCapture: RecordingInputAUHAL
    private let monitorPlayback: RecordingMonitorPlayback
    private let pipeline: RecordingBufferPipeline
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(
        bridgeUID: String,
        monitorUID: String,
        outputURL: URL,
        failureHandler: @escaping @Sendable (RecordingStopReason, String) -> Void
    ) throws {
        let input = try RecordingInputAUHAL(deviceUID: bridgeUID, failureHandler: failureHandler)
        let captureFormat = input.captureFormat
        DiagnosticLog.append(
            "[Recording] AUHAL input format sampleRate=\(captureFormat.sampleRate) " +
            "channels=\(captureFormat.channelCount) interleaved=\(captureFormat.isInterleaved)"
        )
        sampleRate = captureFormat.sampleRate
        channelCount = Int(captureFormat.channelCount)
        let monitor = try RecordingMonitorPlayback(deviceUID: monitorUID, sourceFormat: captureFormat)
        inputCapture = input
        monitorPlayback = monitor
        pipeline = try RecordingBufferPipeline(
            outputURL: outputURL,
            sampleRate: sampleRate,
            channelCount: channelCount,
            failureHandler: failureHandler
        )
        input.setBufferHandler { [pipeline, monitor] buffer in
            pipeline.push(buffer)
            monitor.push(buffer)
        }
        try observeDevice(uid: bridgeUID, stopReason: .sourceDeviceUnavailable, failureHandler: failureHandler)
        try observeDevice(uid: monitorUID, stopReason: .monitorDeviceUnavailable, failureHandler: failureHandler)
    }

    func start() throws {
        try monitorPlayback.start()
        do {
            try inputCapture.start()
        } catch {
            monitorPlayback.stop()
            throw error
        }
    }

    func stopCapture() {
        inputCapture.stop()
        monitorPlayback.stop()
        removeDeviceListeners()
    }

    func finalize() throws {
        try pipeline.finish()
    }

    func verifyMonitorDevice() throws {
        try monitorPlayback.verifyBoundDevice()
    }

    private func observeDevice(
        uid: String,
        stopReason: RecordingStopReason,
        failureHandler: @escaping @Sendable (RecordingStopReason, String) -> Void
    ) throws {
        let id = try RecordingDeviceService.deviceID(uid: uid)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            guard RecordingDeviceService.isAlive(uid: uid) else {
                failureHandler(stopReason, "音频设备已断开：\(uid)")
                return
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(id, &address, .main, block)
        guard status == noErr else { throw RecordingDeviceError.property(status) }
        deviceListeners.append((id, address, block))
    }

    private func removeDeviceListeners() {
        for (id, storedAddress, block) in deviceListeners {
            var address = storedAddress
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        deviceListeners.removeAll()
    }
}

private final class RecordingInputAUHAL: @unchecked Sendable {
    let captureFormat: AVAudioFormat

    private let audioUnit: AudioUnit
    private let renderBuffer: AVAudioPCMBuffer
    private let failureHandler: @Sendable (RecordingStopReason, String) -> Void
    private let frameCapacity: AVAudioFrameCount = 4_096
    private var bufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var started = false
    private var reportedRenderFailure = false

    init(
        deviceUID: String,
        failureHandler: @escaping @Sendable (RecordingStopReason, String) -> Void
    ) throws {
        self.failureHandler = failureHandler

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw RecordingAudioSession.SessionError.unavailableAudioUnit
        }
        var createdUnit: AudioUnit?
        let creationStatus = AudioComponentInstanceNew(component, &createdUnit)
        guard creationStatus == noErr, let createdUnit else {
            throw RecordingDeviceError.property(creationStatus)
        }
        audioUnit = createdUnit

        do {
            var enableInput: UInt32 = 1
            try Self.setProperty(
                createdUnit,
                id: kAudioOutputUnitProperty_EnableIO,
                scope: kAudioUnitScope_Input,
                element: 1,
                value: &enableInput
            )
            var disableOutput: UInt32 = 0
            try Self.setProperty(
                createdUnit,
                id: kAudioOutputUnitProperty_EnableIO,
                scope: kAudioUnitScope_Output,
                element: 0,
                value: &disableOutput
            )
            try RecordingDeviceService.bind(createdUnit, to: deviceUID)

            var deviceFormat = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let formatStatus = AudioUnitGetProperty(
                createdUnit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                1,
                &deviceFormat,
                &formatSize
            )
            guard formatStatus == noErr,
                  deviceFormat.mSampleRate > 0,
                  deviceFormat.mChannelsPerFrame > 0,
                  let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: deviceFormat.mSampleRate,
                    channels: AVAudioChannelCount(deviceFormat.mChannelsPerFrame),
                    interleaved: false
                  ) else {
                if formatStatus != noErr { throw RecordingDeviceError.property(formatStatus) }
                throw RecordingAudioSession.SessionError.invalidInputFormat
            }
            captureFormat = format

            var clientFormat = format.streamDescription.pointee
            try Self.setProperty(
                createdUnit,
                id: kAudioUnitProperty_StreamFormat,
                scope: kAudioUnitScope_Output,
                element: 1,
                value: &clientFormat
            )
            var maximumFrames = UInt32(frameCapacity)
            try Self.setProperty(
                createdUnit,
                id: kAudioUnitProperty_MaximumFramesPerSlice,
                scope: kAudioUnitScope_Global,
                element: 0,
                value: &maximumFrames
            )
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                throw RecordingAudioSession.SessionError.invalidInputFormat
            }
            renderBuffer = buffer
        } catch {
            AudioComponentInstanceDispose(createdUnit)
            throw error
        }

        var callback = AURenderCallbackStruct(
            inputProc: recordingInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        do {
            try Self.setProperty(
                createdUnit,
                id: kAudioOutputUnitProperty_SetInputCallback,
                scope: kAudioUnitScope_Global,
                element: 0,
                value: &callback
            )
        } catch {
            AudioComponentInstanceDispose(createdUnit)
            throw error
        }
    }

    deinit {
        stop()
        AudioComponentInstanceDispose(audioUnit)
    }

    func setBufferHandler(_ handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        bufferHandler = handler
    }

    func start() throws {
        let initializeStatus = AudioUnitInitialize(audioUnit)
        guard initializeStatus == noErr else { throw RecordingDeviceError.property(initializeStatus) }
        let startStatus = AudioOutputUnitStart(audioUnit)
        guard startStatus == noErr else {
            AudioUnitUninitialize(audioUnit)
            throw RecordingDeviceError.property(startStatus)
        }
        started = true
        DiagnosticLog.append("[Recording] input-only AUHAL started")
    }

    func stop() {
        guard started else { return }
        started = false
        AudioOutputUnitStop(audioUnit)
        AudioUnitUninitialize(audioUnit)
        DiagnosticLog.append("[Recording] input-only AUHAL stopped")
    }

    fileprivate func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard frameCount <= frameCapacity else {
            reportRenderFailure(.bufferOverflow, "Audio Bridge 单次输入帧数超过预分配缓冲容量")
            return kAudio_ParamError
        }
        renderBuffer.frameLength = AVAudioFrameCount(frameCount)
        let status = AudioUnitRender(
            audioUnit,
            actionFlags,
            timestamp,
            1,
            frameCount,
            renderBuffer.mutableAudioBufferList
        )
        guard status == noErr else {
            reportRenderFailure(.sourceDeviceUnavailable, "Audio Bridge 输入读取失败（\(status)）")
            return status
        }
        bufferHandler?(renderBuffer)
        return noErr
    }

    private func reportRenderFailure(_ reason: RecordingStopReason, _ message: String) {
        guard !reportedRenderFailure else { return }
        reportedRenderFailure = true
        DiagnosticLog.append("[Recording] AUHAL render failure: \(message)")
        failureHandler(reason, message)
    }

    private static func setProperty<T>(
        _ audioUnit: AudioUnit,
        id: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: inout T
    ) throws {
        let status = withUnsafeBytes(of: &value) { bytes in
            AudioUnitSetProperty(
                audioUnit,
                id,
                scope,
                element,
                bytes.baseAddress,
                UInt32(bytes.count)
            )
        }
        guard status == noErr else { throw RecordingDeviceError.property(status) }
    }
}

private let recordingInputCallback: AURenderCallback = { refCon, actionFlags, timestamp, _, frameCount, _ in
    Unmanaged<RecordingInputAUHAL>
        .fromOpaque(refCon)
        .takeUnretainedValue()
        .render(actionFlags: actionFlags, timestamp: timestamp, frameCount: frameCount)
}

private final class RecordingMonitorPlayback: @unchecked Sendable {
    private let audioUnit: AudioUnit
    private let expectedDeviceID: AudioDeviceID
    private let format: AVAudioFormat
    private let channelCount: Int
    private let frameCapacity = 32_768
    private let samples: UnsafeMutablePointer<Float>
    private let writePosition: UnsafeMutablePointer<Int64>
    private let readPosition: UnsafeMutablePointer<Int64>
    private let stopped: UnsafeMutablePointer<Int32>
    private let primed: UnsafeMutablePointer<Int32>
    private let pushedFrames: UnsafeMutablePointer<Int64>
    private let renderedFrames: UnsafeMutablePointer<Int64>
    private let underflowFrames: UnsafeMutablePointer<Int64>
    private let primingFrameCount = 2_048
    private var started = false

    init(deviceUID: String, sourceFormat: AVAudioFormat) throws {
        channelCount = min(2, Int(sourceFormat.channelCount))
        guard channelCount > 0,
              let monitorFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceFormat.sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
              ) else {
            throw RecordingAudioSession.SessionError.invalidInputFormat
        }
        format = monitorFormat
        expectedDeviceID = try RecordingDeviceService.deviceID(uid: deviceUID)
        samples = .allocate(capacity: frameCapacity * channelCount)
        samples.initialize(repeating: 0, count: frameCapacity * channelCount)
        writePosition = .allocate(capacity: 1)
        writePosition.initialize(to: 0)
        readPosition = .allocate(capacity: 1)
        readPosition.initialize(to: 0)
        stopped = .allocate(capacity: 1)
        stopped.initialize(to: 0)
        primed = .allocate(capacity: 1)
        primed.initialize(to: 0)
        pushedFrames = .allocate(capacity: 1)
        pushedFrames.initialize(to: 0)
        renderedFrames = .allocate(capacity: 1)
        renderedFrames.initialize(to: 0)
        underflowFrames = .allocate(capacity: 1)
        underflowFrames.initialize(to: 0)

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw RecordingAudioSession.SessionError.unavailableAudioUnit
        }
        var createdUnit: AudioUnit?
        let creationStatus = AudioComponentInstanceNew(component, &createdUnit)
        guard creationStatus == noErr, let createdUnit else {
            throw RecordingDeviceError.property(creationStatus)
        }
        audioUnit = createdUnit

        do {
            var enableOutput: UInt32 = 1
            try Self.setProperty(
                createdUnit,
                id: kAudioOutputUnitProperty_EnableIO,
                scope: kAudioUnitScope_Output,
                element: 0,
                value: &enableOutput
            )
            var disableInput: UInt32 = 0
            try Self.setProperty(
                createdUnit,
                id: kAudioOutputUnitProperty_EnableIO,
                scope: kAudioUnitScope_Input,
                element: 1,
                value: &disableInput
            )
            try RecordingDeviceService.bind(createdUnit, to: deviceUID)
            var streamFormat = monitorFormat.streamDescription.pointee
            try Self.setProperty(
                createdUnit,
                id: kAudioUnitProperty_StreamFormat,
                scope: kAudioUnitScope_Input,
                element: 0,
                value: &streamFormat
            )
        } catch {
            AudioComponentInstanceDispose(createdUnit)
            releaseStorage()
            throw error
        }

        var callback = AURenderCallbackStruct(
            inputProc: recordingMonitorCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        do {
            try Self.setProperty(
                createdUnit,
                id: kAudioUnitProperty_SetRenderCallback,
                scope: kAudioUnitScope_Input,
                element: 0,
                value: &callback
            )
        } catch {
            AudioComponentInstanceDispose(createdUnit)
            releaseStorage()
            throw error
        }
    }

    deinit {
        stop()
        AudioComponentInstanceDispose(audioUnit)
        releaseStorage()
    }

    func start() throws {
        let initializeStatus = AudioUnitInitialize(audioUnit)
        guard initializeStatus == noErr else { throw RecordingDeviceError.property(initializeStatus) }
        let startStatus = AudioOutputUnitStart(audioUnit)
        guard startStatus == noErr else {
            AudioUnitUninitialize(audioUnit)
            throw RecordingDeviceError.property(startStatus)
        }
        started = true
        try verifyBoundDevice()
        DiagnosticLog.append(
            "[Recording] output-only monitor AUHAL started deviceID=\(expectedDeviceID) " +
            "sampleRate=\(format.sampleRate) channels=\(channelCount)"
        )
    }

    func stop() {
        OSAtomicCompareAndSwap32Barrier(0, 1, stopped)
        guard started else { return }
        started = false
        AudioOutputUnitStop(audioUnit)
        AudioUnitUninitialize(audioUnit)
        DiagnosticLog.append(
            "[Recording] output-only monitor AUHAL stopped pushedFrames=\(atomicLoad(pushedFrames)) " +
            "renderedFrames=\(atomicLoad(renderedFrames)) underflowFrames=\(atomicLoad(underflowFrames))"
        )
    }

    func verifyBoundDevice() throws {
        var actualDeviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &actualDeviceID,
            &size
        )
        guard status == noErr else { throw RecordingDeviceError.property(status) }
        guard actualDeviceID == expectedDeviceID else {
            DiagnosticLog.append(
                "[Recording] monitor device drift expected=\(expectedDeviceID) actual=\(actualDeviceID)"
            )
            throw RecordingDeviceError.deviceNotFound("监听设备绑定已失效")
        }
        DiagnosticLog.append("[Recording] monitor device verified deviceID=\(actualDeviceID)")
    }

    func push(_ buffer: AVAudioPCMBuffer) {
        guard atomicLoad(stopped) == 0, let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let write = atomicLoad(writePosition)
        let read = atomicLoad(readPosition)
        guard frames > 0, Int64(frameCapacity) - (write - read) >= Int64(frames) else { return }

        let start = Int(write % Int64(frameCapacity))
        let firstCount = min(frames, frameCapacity - start)
        let secondCount = frames - firstCount
        for channel in 0..<channelCount {
            let destination = samples.advanced(by: channel * frameCapacity)
            destination.advanced(by: start).update(from: channels[channel], count: firstCount)
            if secondCount > 0 {
                destination.update(from: channels[channel].advanced(by: firstCount), count: secondCount)
            }
        }
        OSMemoryBarrier()
        OSAtomicAdd64Barrier(Int64(frames), writePosition)
        OSAtomicAdd64Barrier(Int64(frames), pushedFrames)
    }

    fileprivate func render(frameCount: UInt32, outputData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let outputData else { return kAudio_ParamError }
        let requestedFrames = Int(frameCount)
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        for index in buffers.indices {
            guard let data = buffers[index].mData else { continue }
            data.assumingMemoryBound(to: Float.self).initialize(
                repeating: 0,
                count: requestedFrames * Int(buffers[index].mNumberChannels)
            )
            buffers[index].mDataByteSize = UInt32(
                requestedFrames * Int(buffers[index].mNumberChannels) * MemoryLayout<Float>.size
            )
        }
        guard atomicLoad(stopped) == 0 else { return noErr }

        let read = atomicLoad(readPosition)
        let write = atomicLoad(writePosition)
        let available = max(0, write - read)
        if atomicLoad(primed) == 0 {
            guard available >= Int64(primingFrameCount) else {
                OSAtomicAdd64Barrier(Int64(requestedFrames), underflowFrames)
                return noErr
            }
            OSAtomicCompareAndSwap32Barrier(0, 1, primed)
        }
        guard available >= Int64(requestedFrames) else {
            OSAtomicCompareAndSwap32Barrier(1, 0, primed)
            OSAtomicAdd64Barrier(Int64(requestedFrames), underflowFrames)
            return noErr
        }
        let framesToCopy = requestedFrames

        let start = Int(read % Int64(frameCapacity))
        let firstCount = min(framesToCopy, frameCapacity - start)
        let secondCount = framesToCopy - firstCount
        for channel in 0..<min(channelCount, buffers.count) {
            guard let data = buffers[channel].mData else { continue }
            let destination = data.assumingMemoryBound(to: Float.self)
            let source = samples.advanced(by: channel * frameCapacity)
            destination.update(from: source.advanced(by: start), count: firstCount)
            if secondCount > 0 {
                destination.advanced(by: firstCount).update(from: source, count: secondCount)
            }
        }
        OSMemoryBarrier()
        OSAtomicAdd64Barrier(Int64(framesToCopy), readPosition)
        OSAtomicAdd64Barrier(Int64(framesToCopy), renderedFrames)
        return noErr
    }

    private func releaseStorage() {
        samples.deinitialize(count: frameCapacity * channelCount)
        samples.deallocate()
        writePosition.deinitialize(count: 1)
        writePosition.deallocate()
        readPosition.deinitialize(count: 1)
        readPosition.deallocate()
        stopped.deinitialize(count: 1)
        stopped.deallocate()
        primed.deinitialize(count: 1)
        primed.deallocate()
        pushedFrames.deinitialize(count: 1)
        pushedFrames.deallocate()
        renderedFrames.deinitialize(count: 1)
        renderedFrames.deallocate()
        underflowFrames.deinitialize(count: 1)
        underflowFrames.deallocate()
    }

    private static func setProperty<T>(
        _ audioUnit: AudioUnit,
        id: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: inout T
    ) throws {
        let status = withUnsafeBytes(of: &value) { bytes in
            AudioUnitSetProperty(audioUnit, id, scope, element, bytes.baseAddress, UInt32(bytes.count))
        }
        guard status == noErr else { throw RecordingDeviceError.property(status) }
    }
}

private let recordingMonitorCallback: AURenderCallback = { refCon, _, _, _, frameCount, outputData in
    Unmanaged<RecordingMonitorPlayback>
        .fromOpaque(refCon)
        .takeUnretainedValue()
        .render(frameCount: frameCount, outputData: outputData)
}

private final class RecordingBufferPipeline: @unchecked Sendable {
    private let slotCount: Int32 = 64
    private let frameCapacity = 4_096
    private let channelCount: Int
    private let samples: UnsafeMutablePointer<Float>
    private let frameCounts: UnsafeMutablePointer<Int32>
    private let writer: RecordingWAVWriter
    private let queue = DispatchQueue(label: "com.shengjiacheng.GetOudio.recording-writer", qos: .userInitiated)
    private let wake = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let failureHandler: @Sendable (RecordingStopReason, String) -> Void
    private let writePosition: UnsafeMutablePointer<Int64>
    private let readPosition: UnsafeMutablePointer<Int64>
    private let stopping: UnsafeMutablePointer<Int32>
    private var writerError: Error?
    private var loggedFirstBuffer = false

    init(
        outputURL: URL,
        sampleRate: Double,
        channelCount: Int,
        failureHandler: @escaping @Sendable (RecordingStopReason, String) -> Void
    ) throws {
        self.channelCount = channelCount
        self.failureHandler = failureHandler
        samples = .allocate(capacity: Int(slotCount) * frameCapacity * channelCount)
        samples.initialize(repeating: 0, count: Int(slotCount) * frameCapacity * channelCount)
        frameCounts = .allocate(capacity: Int(slotCount))
        frameCounts.initialize(repeating: 0, count: Int(slotCount))
        writePosition = .allocate(capacity: 1)
        writePosition.initialize(to: 0)
        readPosition = .allocate(capacity: 1)
        readPosition.initialize(to: 0)
        stopping = .allocate(capacity: 1)
        stopping.initialize(to: 0)
        writer = try RecordingWAVWriter(url: outputURL, sampleRate: sampleRate, channelCount: channelCount)
        queue.async { [self] in writerLoop() }
    }

    deinit {
        samples.deinitialize(count: Int(slotCount) * frameCapacity * channelCount)
        samples.deallocate()
        frameCounts.deinitialize(count: Int(slotCount))
        frameCounts.deallocate()
        writePosition.deinitialize(count: 1)
        writePosition.deallocate()
        readPosition.deinitialize(count: 1)
        readPosition.deallocate()
        stopping.deinitialize(count: 1)
        stopping.deallocate()
    }

    func push(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        guard atomicLoad(stopping) == 0 else { return }
        let frames = Int(buffer.frameLength)
        let write = atomicLoad(writePosition)
        let read = atomicLoad(readPosition)
        guard frames <= frameCapacity, write - read < Int64(slotCount) else {
            failureHandler(.bufferOverflow, RecordingAudioSession.SessionError.bufferOverflow.localizedDescription)
            return
        }

        let slot = Int(write % Int64(slotCount))
        let slotBase = samples.advanced(by: slot * frameCapacity * channelCount)
        for channel in 0..<channelCount {
            slotBase.advanced(by: channel * frameCapacity).update(from: channels[channel], count: frames)
        }
        frameCounts[slot] = Int32(frames)
        OSMemoryBarrier()
        OSAtomicAdd64Barrier(1, writePosition)
        wake.signal()
    }

    func finish() throws {
        OSAtomicCompareAndSwap32Barrier(0, 1, stopping)
        wake.signal()
        finished.wait()
        if let writerError { throw writerError }
    }

    private func writerLoop() {
        while true {
            wake.wait()
            while drainOne() {}

            if isStoppedAndDrained() {
                do { try writer.finalize() } catch { writerError = error }
                finished.signal()
                return
            }
        }
    }

    private func drainOne() -> Bool {
        let read = atomicLoad(readPosition)
        guard read < atomicLoad(writePosition) else { return false }
        let slot = Int(read % Int64(slotCount))
        let frames = Int(frameCounts[slot])
        let slotSamples = UnsafePointer(samples.advanced(by: slot * frameCapacity * channelCount))
        do {
            try writer.write(
                planarSamples: slotSamples,
                frameCount: frames,
                planeStride: frameCapacity
            )
            if !loggedFirstBuffer {
                loggedFirstBuffer = true
                DiagnosticLog.append("[Recording] first captured buffer received frames=\(frames)")
            }
        } catch {
            writerError = error
            failureHandler(.writerFailure, error.localizedDescription)
            OSAtomicCompareAndSwap32Barrier(0, 1, stopping)
        }
        OSMemoryBarrier()
        OSAtomicAdd64Barrier(1, readPosition)
        return true
    }

    private func isStoppedAndDrained() -> Bool {
        return atomicLoad(stopping) != 0 && atomicLoad(readPosition) == atomicLoad(writePosition)
    }
}

private func atomicLoad(_ pointer: UnsafeMutablePointer<Int64>) -> Int64 {
    OSAtomicAdd64Barrier(0, pointer)
}

private func atomicLoad(_ pointer: UnsafeMutablePointer<Int32>) -> Int32 {
    OSAtomicAdd32Barrier(0, pointer)
}
