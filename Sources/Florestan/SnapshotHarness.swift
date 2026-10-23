import AppKit
import SwiftUI

/// Development aid: `Florestan --snapshot <dir>` opens the window, saves a PNG of each section and of the menu bar
/// panel, and quits. Uses the app's own window contents, so it needs no Screen Recording permission.
/// With `FLORESTAN_HOME` set (see AppModel), it shows a demo state instead of the real library's records.
@MainActor
enum SnapshotHarness {
    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    static func run(model: AppModel, menuPanel: some View, showWindow: @escaping () -> Void) {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        showWindow()
        Task {
            try? await Task.sleep(for: .seconds(2))
            for section in Section.allCases {
                model.selectedSection = section
                try? await Task.sleep(for: .seconds(section == .forYou ? 15 : 1.2))
                guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true && $0.isVisible }),
                      let view = window.contentView?.superview ?? window.contentView else { continue }
                save(view, to: dir.appendingPathComponent("\(section.rawValue).png"))
            }
            await savePanel(menuPanel, to: dir.appendingPathComponent("menu-panel.png"))
            NSApp.terminate(nil)
        }
    }

    /// The menu bar panel, shown in a window of its own: the real one only opens from a click on the menu bar.
    private static func savePanel(_ panel: some View, to file: URL) async {
        let hosting = NSHostingView(rootView: panel.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        window.orderFront(nil)
        try? await Task.sleep(for: .seconds(3))
        save(hosting, to: file)
        window.orderOut(nil)
    }

    private static func save(_ view: NSView, to file: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}
