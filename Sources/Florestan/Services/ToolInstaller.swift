import Foundation

/// Florestan carries yt-dlp, deno, ffmpeg and ffprobe inside its app bundle (Contents/Resources/Tools), so it
/// works on a Mac without Homebrew. On launch they're copied to ~/Library/Application Support/Florestan/bin,
/// where yt-dlp can update itself; a copy is only replaced when the app brings a newer one.
enum ToolInstaller {
    static let binFolder = AppModel.supportFolder.appendingPathComponent("bin", isDirectory: true)
    static let tools = ["yt-dlp", "deno", "ffmpeg", "ffprobe"]

    private static var bundledFolder: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("Tools", isDirectory: true)
        return url.flatMap { FileManager.default.fileExists(atPath: $0.appendingPathComponent("VERSIONS").path) ? $0 : nil }
    }

    /// Copies bundled tools that are missing or older than the bundle's. Safe to call on every launch.
    static func installBundledTools() {
        guard let bundled = bundledFolder else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: binFolder, withIntermediateDirectories: true)
        let bundledVersions = versions(in: bundled.appendingPathComponent("VERSIONS"))
        let installedVersions = versions(in: binFolder.appendingPathComponent("VERSIONS"))

        for tool in tools {
            let source = bundled.appendingPathComponent(tool)
            let target = binFolder.appendingPathComponent(tool)
            guard fm.fileExists(atPath: source.path) else { continue }
            let key = tool == "ffprobe" ? "ffmpeg" : tool
            let missing = !fm.isExecutableFile(atPath: target.path)
            // yt-dlp versions are dates (2026.08.19), so a plain comparison tells which is newer; it may have updated itself past the bundle.
            let outdated = key == "yt-dlp"
                ? (installedVersions[key] ?? "") < (bundledVersions[key] ?? "")
                : installedVersions[key] != bundledVersions[key]
            guard missing || outdated else { continue }
            try? fm.removeItem(at: target)
            do {
                try fm.copyItem(at: source, to: target)
                // Copied out of a downloaded app, the file carries its quarantine flag, which would block running it.
                removexattr(target.path, "com.apple.quarantine", 0)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            } catch {
                continue
            }
        }
        try? fm.removeItem(at: binFolder.appendingPathComponent("VERSIONS"))
        try? fm.copyItem(at: bundled.appendingPathComponent("VERSIONS"), to: binFolder.appendingPathComponent("VERSIONS"))
    }

    static var usesBundledYTDLP: Bool {
        Shell.locate("yt-dlp")?.deletingLastPathComponent().standardizedFileURL == binFolder.standardizedFileURL
    }

    private static func versions(in file: URL) -> [String: String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }
}
