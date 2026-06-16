import AppKit
import Sparkle

/// Wraps Sparkle's standard updater. The feed URL + public EdDSA key live in Info.plist
/// (`SUFeedURL`, `SUPublicEDKey`); releases are published to GitHub with a signed appcast.
///
/// Sparkle refuses to start without a public key, and an unreachable placeholder feed throws an
/// error dialog. Until the project is configured with a real repo + key, we keep Sparkle dormant
/// and fall back to opening the Releases page, so a fresh checkout never shows an "update failed"
/// error on launch.
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController?

    let isConfigured: Bool

    init() {
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        isConfigured = !key.isEmpty && !feed.contains("your-name") && !feed.isEmpty

        if isConfigured {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
    }

    func checkForUpdates() {
        if let controller {
            controller.updater.checkForUpdates()
        } else {
            // Not wired to a real appcast yet — send the user to the Releases page.
            NSWorkspace.shared.open(AppInfo.githubURL.appendingPathComponent("releases"))
        }
    }
}
