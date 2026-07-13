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
    private let realtimeIssues: RecordingRealtimeIssues
    private let inputDiagnostics: RecordingInputDiagnostics
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(
        bridgeUID: String,
        monitorUID: String,
        outputURL: URL,
        failureHandler: @escaping @Sendable (RecordingStopReason, String) -> Void
    ) throws {
        let realtimeIssues = RecordingRealtimeIssues()
        let inputDiagnostics = RecordingInputDiagnostics()
        let input = try RecordingInputAUHAL(
            deviceUID: bridgeUID,
            realtimeIssues: realtimeIssues,
            diagnostics: inputDiagnostics
        )
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
        self.realtimeIssues = realtimeIssues
        self.inputDiagnostics = inputDiagnostics
        pipeline = try RecordingBufferPipeline(
            outputURL: outputURL,
            sampleRate: sampleRate,
            channelCount: channelCount,
            realtimeIssues: realtimeIssues,
            diagnostics: inputDiagnostics,
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

    func takeRealtimeIssue() -> (reason: RecordingStopReason, message: String)? {
        realtimeIssues.take()
    }

    func inputDiagnosticSnapshot() -> RecordingInputDiagnostics.Snapshot {
        inputDiagnostics.snapshot()
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
    private let realtimeIssues: RecordingRealtimeIssues
    private let diagnostics: RecordingInputDiagnostics
    private let frameCapacity: AVAudioFrameCount = 4_096
    private var bufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var started = false

    init(
        deviceUID: String,
        realtimeIssues: RecordingRealtimeIssues,
        diagnostics: RecordingInputDiagnostics
    ) throws {
        self.realtimeIssues = realtimeIssues
        self.diagnostics = diagnostics

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
            realtimeIssues.record(.inputFrameCapacityExceeded)
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
            realtimeIssues.record(.inputRenderFailed, status: status)
            return status
        }
        diagnostics.recordCallback(timestamp.pointee)
        bufferHandler?(renderBuffer)
        return noErr
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
    private let droppedFrames: UnsafeMutablePointer<Int64>
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
        droppedFrames = .allocate(capacity: 1)
        droppedFrames.initialize(to: 0)

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
            "renderedFrames=\(atomicLoad(renderedFrames)) underflowFrames=\(atomicLoad(underflowFrames)) " +
            "droppedFrames=\(atomicLoad(droppedFrames))"
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
        guard frames > 0 else { return }
        guard Int64(frameCapacity) - (write - read) >= Int64(frames) else {
            OSAtomicAdd64Barrier(Int64(frames), droppedFrames)
            return
        }

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
            let byteCount = requestedFrames * Int(buffers[index].mNumberChannels) * MemoryLayout<Float>.size
            memset(data, 0, byteCount)
            buffers[index].mDataByteSize = UInt32(
                byteCount
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
        droppedFrames.deinitialize(count: 1)
        droppedFrames.deallocate()
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

/// Carries a bounded error code out of a Core Audio callback. Formatting, logging and stopping
/// happen later on the runner's main queue, never on the realtime thread.
private final class RecordingRealtimeIssues: @unchecked Sendable {
    fileprivate enum Code: Int32 {
        case none
        case bufferOverflow
        case inputFrameCapacityExceeded
        case inputRenderFailed
    }

    private let code = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private let status = UnsafeMutablePointer<Int64>.allocate(capacity: 1)

    init() {
        code.initialize(to: Code.none.rawValue)
        status.initialize(to: Int64(noErr))
    }

    deinit {
        code.deinitialize(count: 1)
        code.deallocate()
        status.deinitialize(count: 1)
        status.deallocate()
    }

    func record(_ newCode: Code, status newStatus: OSStatus = noErr) {
        guard newCode != .none else { return }
        atomicStore(Int64(newStatus), at: status)
        OSMemoryBarrier()
        _ = OSAtomicCompareAndSwap32Barrier(Code.none.rawValue, newCode.rawValue, code)
    }

    func take() -> (reason: RecordingStopReason, message: String)? {
        let current = atomicLoad(code)
        guard let issue = Code(rawValue: current), issue != .none,
              OSAtomicCompareAndSwap32Barrier(current, Code.none.rawValue, code) else {
            return nil
        }
        switch issue {
        case .bufferOverflow:
            return (.bufferOverflow, RecordingAudioSession.SessionError.bufferOverflow.localizedDescription)
        case .inputFrameCapacityExceeded:
            return (.bufferOverflow, "Audio Bridge 单次输入帧数超过预分配缓冲容量")
        case .inputRenderFailed:
            return (.sourceDeviceUnavailable, "Audio Bridge 输入读取失败（\(atomicLoad(status))）")
        case .none:
            return nil
        }
    }
}

final class RecordingInputDiagnostics: @unchecked Sendable {
    struct Snapshot {
        let callbackCount: Int64
        let writtenFrameCount: Int64
        let nonSilentBlockCount: Int64
        let lastSampleTime: Double
        let lastHostTime: UInt64
    }

    private let callbackCount = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
    private let writtenFrameCount = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
    private let nonSilentBlockCount = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
    private let lastSampleTimeBits = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
    private let lastHostTime = UnsafeMutablePointer<Int64>.allocate(capacity: 1)

    init() {
        callbackCount.initialize(to: 0)
        writtenFrameCount.initialize(to: 0)
        nonSilentBlockCount.initialize(to: 0)
        lastSampleTimeBits.initialize(to: 0)
        lastHostTime.initialize(to: 0)
    }

    deinit {
        callbackCount.deinitialize(count: 1)
        callbackCount.deallocate()
        writtenFrameCount.deinitialize(count: 1)
        writtenFrameCount.deallocate()
        nonSilentBlockCount.deinitialize(count: 1)
        nonSilentBlockCount.deallocate()
        lastSampleTimeBits.deinitialize(count: 1)
        lastSampleTimeBits.deallocate()
        lastHostTime.deinitialize(count: 1)
        lastHostTime.deallocate()
    }

    func recordCallback(_ timestamp: AudioTimeStamp) {
        atomicStore(Int64(bitPattern: timestamp.mHostTime), at: lastHostTime)
        atomicStore(Int64(bitPattern: timestamp.mSampleTime.bitPattern), at: lastSampleTimeBits)
        OSAtomicAdd64Barrier(1, callbackCount)
    }

    func recordWrittenBlock(
        planarSamples: UnsafePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        planeStride: Int
    ) {
        guard frameCount > 0 else { return }
        var hasSignal = false
        for channel in 0..<channelCount where !hasSignal {
            let samples = planarSamples.advanced(by: channel * planeStride)
            for frame in 0..<frameCount where samples[frame] != 0 {
                hasSignal = true
                break
            }
        }
        if hasSignal { OSAtomicAdd64Barrier(1, nonSilentBlockCount) }
        OSAtomicAdd64Barrier(Int64(frameCount), writtenFrameCount)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            callbackCount: atomicLoad(callbackCount),
            writtenFrameCount: atomicLoad(writtenFrameCount),
            nonSilentBlockCount: atomicLoad(nonSilentBlockCount),
            lastSampleTime: Double(bitPattern: UInt64(bitPattern: atomicLoad(lastSampleTimeBits))),
            lastHostTime: UInt64(bitPattern: atomicLoad(lastHostTime))
        )
    }
}

private final class RecordingBufferPipeline: @unchecked Sendable {
    private let slotCount: Int32 = 64
    private let frameCapacity = 4_096
    private let channelCount: Int
    private let samples: UnsafeMutablePointer<Float>
    private let frameCounts: UnsafeMutablePointer<Int32>
    private let writer: RecordingWAVWriter
    private let queue = DispatchQueue(label: "com.shengjiacheng.GetOudio.recording-writer", qos: .userInitiated)
    private let writerTimer: DispatchSourceTimer
    private let finished = DispatchSemaphore(value: 0)
    private let realtimeIssues: RecordingRealtimeIssues
    private let diagnostics: RecordingInputDiagnostics
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
        realtimeIssues: RecordingRealtimeIssues,
        diagnostics: RecordingInputDiagnostics,
        failureHandler: @escaping @Sendable (RecordingStopReason, String) -> Void
    ) throws {
        self.channelCount = channelCount
        self.realtimeIssues = realtimeIssues
        self.diagnostics = diagnostics
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
        writerTimer = DispatchSource.makeTimerSource(queue: queue)
        writerTimer.setEventHandler { [weak self] in self?.drainPendingBuffers() }
        writerTimer.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .milliseconds(1))
        writerTimer.resume()
    }

    deinit {
        writerTimer.cancel()
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
            realtimeIssues.record(.bufferOverflow)
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
    }

    func finish() throws {
        OSAtomicCompareAndSwap32Barrier(0, 1, stopping)
        finished.wait()
        if let writerError { throw writerError }
    }

    private func drainPendingBuffers() {
        while drainOne() {}
        if isStoppedAndDrained() {
            do { try writer.finalize() } catch { writerError = error }
            writerTimer.cancel()
            finished.signal()
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
            diagnostics.recordWrittenBlock(
                planarSamples: slotSamples,
                frameCount: frames,
                channelCount: channelCount,
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

private func atomicStore(_ value: Int64, at pointer: UnsafeMutablePointer<Int64>) {
    var current = atomicLoad(pointer)
    while !OSAtomicCompareAndSwap64Barrier(current, value, pointer) {
        current = atomicLoad(pointer)
    }
}
