import Combine
import Foundation
import GetOudioCore

@MainActor
final class NCMSettingsModel: ObservableObject {
    @Published var ncmOutputMode: String
    @Published var ncmCustomOutputURL: URL?

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        ncmOutputMode = store.ncmOutputMode
        ncmCustomOutputURL = store.ncmCustomOutputURL
    }

    func setNCMOutputMode(_ mode: String) {
        ncmOutputMode = mode
        store.ncmOutputMode = mode
    }

    func chooseNCMOutputDirectory() {
        guard let url = DirectoryChooser.chooseDirectory(prompt: "选择") else { return }
        ncmCustomOutputURL = url
        store.ncmCustomOutputURL = url
        setNCMOutputMode("customDirectory")
    }
}
