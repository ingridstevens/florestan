import AppKit
import FlorestanCore
import SwiftUI
import UserNotifications

@main
struct FlorestanApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(delegate.model)
                .environment(delegate.eusebius)
                .environment(delegate.recommendations)
        } label: {
            MenuBarLabel(delegate: delegate)
        }
        .menuBarExtraStyle(.window)

        Window("Florestan.exe", id: "main") {
            MainWindow()
                .environment(delegate.model)
                .environment(delegate.eusebius)
                .environment(delegate.recommendations)
                .tint(delegate.model.settings.theme.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 900, height: 620)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// The menu bar icon. Also hands the window-opening action to the app delegate, which has no SwiftUI environment.
private struct MenuBarLabel: View {
    var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: delegate.model.isBusy ? "arrow.down.circle.dotted" : "music.note")
            .accessibilityLabel("Florestan.exe")
            .task { delegate.windowOpener = { openWindow(id: "main") } }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let eusebius = EusebiusModel()
    let recommendations = RecommendationsModel()
    private var hotKey: HotKey?
    var windowOpener: (() -> Void)? {
        didSet {
            if SnapshotHarness.outputDirectory != nil {
                let panel = MenuPanel().environment(model).environment(eusebius).environment(recommendations)
                SnapshotHarness.run(model: model, menuPanel: panel) { [weak self] in self?.showWindow() }
                return
            }
            // Show the window the very first time Florestan runs, so it doesn't seem to do nothing.
            guard windowOpener != nil, !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") else { return }
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            showWindow()
        }
    }

    func showWindow() {
        windowOpener?()
        NSApp.activate()
    }

    /// Opening the app again from Finder, Spotlight or the Dock shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Notifier.requestPermission()
        if Bundle.main.bundleURL.pathExtension == "app" { UNUserNotificationCenter.current().delegate = self }
        hotKey = HotKey { [weak self] in
            Task { @MainActor in self?.downloadClipboard() }
        }
    }

    /// ⌥⌘Y: download whatever link is on the clipboard.
    private func downloadClipboard() {
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        switch model.submit(clip) {
        case .queued:
            let kind = Link.parse(clip)?.isPlaylist == true ? "playlist" : "song"
            Notifier.post(title: "Downloading \(kind)", body: "Florestan will add it to Apple Music.")
        case .notALink:
            Notifier.post(title: "No YouTube link on the clipboard", body: "Copy a YouTube or YouTube Music link, then press ⌥⌘Y.")
        case .alreadyQueued:
            Notifier.post(title: "Already downloading", body: "That link is in the queue.")
        case .toolsMissing:
            Notifier.post(title: "Florestan needs yt-dlp and ffmpeg", body: "Run: brew install yt-dlp ffmpeg")
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show banners even while Florestan is the active app (e.g. with its window open).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Clicking a "done" notification opens the result in Apple Music.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo[Notifier.jobIDKey] as? String,
              let jobID = UUID(uuidString: raw) else { return }
        await MainActor.run { model.openInAppleMusic(jobID: jobID) }
    }
}
