import Foundation
import UserNotifications

/// macOS notifications: one per finished Job.
enum Notifier {
    /// UNUserNotificationCenter crashes outside an app bundle (e.g. `swift run`).
    private static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    static func jobFinished(_ job: Job) {
        let body: String
        switch job.phase {
        case .failed(let why):
            body = why
        default:
            if job.link.isPlaylist {
                var s = job.importedCount == 1 ? "1 song added to Apple Music" : "\(job.importedCount) songs added to Apple Music"
                if job.failedCount > 0 { s += " (\(job.failedCount) failed)" }
                body = s
            } else {
                body = job.importedCount == 1 ? "Added to Apple Music" : job.skippedCount == 1 ? "Already in your library" : "Not added"
            }
        }
        post(title: job.title, body: body)
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
