import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdateService: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isUpdateChecksEnabled: Bool

    private let updaterController: SPUStandardUpdaterController?
    private var updateAvailabilityCancellable: AnyCancellable?

    init(bundle: Bundle = .main) {
        let updatesEnabled = Self.resolveUpdatesEnabled(in: bundle)
        isUpdateChecksEnabled = updatesEnabled

        guard updatesEnabled else {
            updaterController = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller

        updateAvailabilityCancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
    }

    func checkForUpdates() {
        guard isUpdateChecksEnabled else {
            return
        }

        updaterController?.checkForUpdates(nil)
    }

    private static func resolveUpdatesEnabled(in bundle: Bundle) -> Bool {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "PPUpdatesEnabled") else {
            return true
        }

        if let boolValue = rawValue as? Bool {
            return boolValue
        }

        if let numericValue = rawValue as? NSNumber {
            return numericValue.boolValue
        }

        if let stringValue = rawValue as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return true
            }
        }

        return true
    }
}
