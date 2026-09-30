import Foundation
import Observation
import ServiceManagement

/// User preferences, persisted in UserDefaults.
@MainActor @Observable
final class Settings {
    private let defaults = UserDefaults.standard

    var theme: FrameTheme {
        didSet { defaults.set(theme.rawValue, forKey: "theme") }
    }
    var keepYTDLPUpdated: Bool {
        didSet { defaults.set(keepYTDLPUpdated, forKey: "keepYTDLPUpdated") }
    }
    var useBrowserLogin: Bool {
        didSet { defaults.set(useBrowserLogin, forKey: "useBrowserLogin") }
    }
    var cookieBrowser: CookieBrowser {
        didSet { defaults.set(cookieBrowser.rawValue, forKey: "cookieBrowser") }
    }
    /// Look up the album of songs from plain YouTube videos right after they download.
    var tidyNewSongs: Bool {
        didSet { defaults.set(tidyNewSongs, forKey: "tidyNewSongs") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            launchAtLoginRevision += 1
        }
    }
    /// Bumped so views re-read `launchAtLogin`, which Observation can't track.
    private(set) var launchAtLoginRevision = 0

    init() {
        theme = FrameTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .dusk
        keepYTDLPUpdated = defaults.object(forKey: "keepYTDLPUpdated") as? Bool ?? true
        useBrowserLogin = defaults.bool(forKey: "useBrowserLogin")
        cookieBrowser = CookieBrowser(rawValue: defaults.string(forKey: "cookieBrowser") ?? "") ?? .safari
        tidyNewSongs = defaults.object(forKey: "tidyNewSongs") as? Bool ?? true
    }

    var ytdlpUpgradeDue: Bool {
        guard let last = defaults.object(forKey: "lastYTDLPUpgrade") as? Date else { return true }
        return Date.now.timeIntervalSince(last) > 24 * 60 * 60
    }

    func markYTDLPUpgraded() {
        defaults.set(Date.now, forKey: "lastYTDLPUpgrade")
    }
}
