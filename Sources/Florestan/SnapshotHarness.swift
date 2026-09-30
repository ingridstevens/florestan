import AppKit

/// Development aid: `Florestan --snapshot <dir>` opens the window, saves a PNG of each section, and quits.
/// Uses the app's own window contents, so it needs no Screen Recording permission.
@MainActor
enum SnapshotHarness {
    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    static func run(model: AppModel, showWindow: @escaping () -> Void) {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        showWindow()
        Task {
            try? await Task.sleep(for: .seconds(2))
            for section in Section.allCases {
                model.selectedSection = section
                try? await Task.sleep(for: .seconds(1.2))
                guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true && $0.isVisible }),
                      let view = window.contentView?.superview ?? window.contentView else { continue }
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: dir.appendingPathComponent("\(section.rawValue).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }
}
