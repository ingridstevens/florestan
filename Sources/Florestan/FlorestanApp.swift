import AppKit
import FlorestanCore
import SwiftUI
import UserNotifications

@main
struct FlorestanApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        SingleInstance.handOffIfAlreadyRunning()
    }

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

/// Florestan runs once. A second copy, say one opened again from the disk image, would share the first one's
/// history and Ledger and overwrite its changes, so it asks the running copy to show its window and quits before
/// reading anything.
enum SingleInstance {
    static let showWindowRequest = Notification.Name("local.florestan.showWindow")

    static func handOffIfAlreadyRunning() {
        // A bare build has no bundle ID, and the screenshots' demo state keeps its own files.
        guard AppModel.homeOverride == nil, let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0 != .current }
        guard let running = others.first else { return }
        DistributedNotificationCenter.default().postNotificationName(showWindowRequest, object: nil, userInfo: nil, deliverImmediately: true)
        running.activate()
        exit(0)
    }
}

/// The menu bar icon. Also hands the window-opening action to the app delegate, which has no SwiftUI environment.
private struct MenuBarLabel: View {
    var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: delegate.menuBarIcon.image)
            .task { delegate.windowOpener = { openWindow(id: "main") } }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let eusebius = EusebiusModel()
    let recommendations = RecommendationsModel()
    lazy var menuBarIcon = MenuBarAnimator(model: model)
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
        DistributedNotificationCenter.default().addObserver(forName: SingleInstance.showWindowRequest, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showWindow() }
        }
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
        case .alreadyQueued(let title, let running):
            Notifier.post(title: running ? "Already downloading" : "Already waiting",
                          body: AppModel.alreadyQueuedMessage(title: title, running: running))
        case .alreadyInLibrary(let title):
            Notifier.post(title: "Already in your library", body: AppModel.alreadyInLibraryMessage(title: title))
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
