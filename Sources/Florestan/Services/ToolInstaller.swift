import CryptoKit
import Foundation

/// Florestan carries yt-dlp, deno, ffmpeg and ffprobe inside its app bundle (Contents/Resources/Tools), so it
/// works on a Mac without Homebrew. On launch they're copied to ~/Library/Application Support/Florestan/bin;
/// a copy is only replaced when the app brings a newer one.
///
/// yt-dlp is the unpacked build: a folder per version (`bin/yt-dlp-2026.10.21/`) with `bin/yt-dlp` linking to
/// the current one. Unpacked once, it starts in a fraction of a second; the single-file build unpacks itself on
/// every run and waits about 20 seconds for macOS to check the new files. yt-dlp can't update this build itself,
/// so `updateYTDLP` fetches new releases.
enum ToolInstaller {
    static let binFolder = AppModel.supportFolder.appendingPathComponent("bin", isDirectory: true)
    static let tools = ["deno", "ffmpeg", "ffprobe"]

    private static let ytdlpLink = binFolder.appendingPathComponent("yt-dlp")
    private static let ytdlpFolderPrefix = "yt-dlp-"
    /// The executable inside the unpacked build.
    private static let ytdlpExecutable = "yt-dlp_macos"

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
            guard missing || installedVersions[key] != bundledVersions[key] else { continue }
            try? fm.removeItem(at: target)
            do {
                try fm.copyItem(at: source, to: target)
                // Copied out of a downloaded app, the file carries its quarantine flag, which would block running it.
                removeQuarantine(at: target)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            } catch {
                continue
            }
        }
        installBundledYTDLP(from: bundled.appendingPathComponent(ytdlpExecutable), version: bundledVersions["yt-dlp"])
        removeOldYTDLPs()
        try? fm.removeItem(at: binFolder.appendingPathComponent("VERSIONS"))
        try? fm.copyItem(at: bundled.appendingPathComponent("VERSIONS"), to: binFolder.appendingPathComponent("VERSIONS"))
    }

    /// Installs the bundle's yt-dlp unless the installed one is the same or newer. A single-file yt-dlp from an
    /// earlier Florestan is always replaced, whatever its version.
    private static func installBundledYTDLP(from source: URL, version: String?) {
        let fm = FileManager.default
        guard let version, fm.isExecutableFile(atPath: source.appendingPathComponent(ytdlpExecutable).path) else { return }
        // yt-dlp versions are dates (2026.08.19), so a plain comparison tells which is newer; it may have been updated past the bundle.
        if let installed = installedYTDLPVersion, installed >= version { return }
        let target = binFolder.appendingPathComponent(ytdlpFolderPrefix + version)
        try? fm.removeItem(at: target)
        do {
            try fm.copyItem(at: source, to: target)
            removeQuarantine(at: target)
            try linkYTDLP(to: target)
        } catch {
            try? fm.removeItem(at: target)
        }
    }

    static var usesBundledYTDLP: Bool {
        Shell.locate("yt-dlp")?.deletingLastPathComponent().standardizedFileURL == binFolder.standardizedFileURL
    }

    /// The version of the unpacked yt-dlp `bin/yt-dlp` links to, read from its folder's name.
    /// Nil when it's missing or a single-file build.
    static var installedYTDLPVersion: String? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: ytdlpLink.path) else { return nil }
        let folder = destination.split(separator: "/").first.map(String.init) ?? ""
        guard folder.hasPrefix(ytdlpFolderPrefix) else { return nil }
        return String(folder.dropFirst(ytdlpFolderPrefix.count))
    }

    /// Fetches yt-dlp's latest release if it's newer than the installed one, checks it against the release's
    /// checksums, makes sure it runs, then switches `bin/yt-dlp` over to it. Songs downloading meanwhile keep
    /// using the old copy, which goes on the next launch. Returns true if yt-dlp is up to date afterwards.
    static func updateYTDLP() async -> Bool {
        guard let current = installedYTDLPVersion else { return false }
        struct Release: Decodable { var tag_name: String }
        let api = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        guard let (data, response) = try? await URLSession.shared.data(from: api),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = try? JSONDecoder().decode(Release.self, from: data).tag_name else { return false }
        guard latest > current else { return true }

        let fm = FileManager.default
        let release = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\(latest)/")!
        guard let (zip, zipResponse) = try? await URLSession.shared.download(from: release.appendingPathComponent("yt-dlp_macos.zip")),
              (zipResponse as? HTTPURLResponse)?.statusCode == 200 else { return false }
        defer { try? fm.removeItem(at: zip) }
        guard let (sums, _) = try? await URLSession.shared.data(from: release.appendingPathComponent("SHA2-256SUMS")),
              let zipData = try? Data(contentsOf: zip) else { return false }
        let digest = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        let expected = String(decoding: sums, as: UTF8.self).split(separator: "\n")
            .first { $0.hasSuffix(" yt-dlp_macos.zip") }?.split(separator: " ").first.map(String.init)
        guard expected == digest else { return false }

        // Unpacked beside the others under a hidden name, so a half-finished copy is never linked or kept.
        let staging = binFolder.appendingPathComponent(".\(ytdlpFolderPrefix)\(latest)")
        let target = binFolder.appendingPathComponent(ytdlpFolderPrefix + latest)
        try? fm.removeItem(at: staging)
        guard (try? await Shell.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, staging.path]))?.succeeded == true else {
            try? fm.removeItem(at: staging)
            return false
        }
        // Its first run is the slow one while macOS checks the new files; better here than on a song.
        let version = try? await Shell.run(staging.appendingPathComponent(ytdlpExecutable), ["--version"])
        guard version?.succeeded == true else {
            try? fm.removeItem(at: staging)
            return false
        }
        do {
            try? fm.removeItem(at: target)
            try fm.moveItem(at: staging, to: target)
            try linkYTDLP(to: target)
            return true
        } catch {
            try? fm.removeItem(at: staging)
            return false
        }
    }

    /// Points `bin/yt-dlp` at an unpacked yt-dlp in one step, so nothing ever finds the link missing.
    private static func linkYTDLP(to folder: URL) throws {
        let fm = FileManager.default
        let temporary = binFolder.appendingPathComponent(".yt-dlp-link")
        try? fm.removeItem(at: temporary)
        try fm.createSymbolicLink(atPath: temporary.path, withDestinationPath: "\(folder.lastPathComponent)/\(ytdlpExecutable)")
        if rename(temporary.path, ytdlpLink.path) != 0 {
            try? fm.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Deletes yt-dlp folders other than the current one, and unfinished updates. Runs at launch, before any song downloads.
    private static func removeOldYTDLPs() {
        let fm = FileManager.default
        let current = installedYTDLPVersion.map { ytdlpFolderPrefix + $0 }
        let names = (try? fm.contentsOfDirectory(atPath: binFolder.path)) ?? []
        for name in names where name.hasPrefix(ytdlpFolderPrefix) || name.hasPrefix(".\(ytdlpFolderPrefix)") {
            if name != current { try? fm.removeItem(at: binFolder.appendingPathComponent(name)) }
        }
    }

    /// Removes the quarantine flag from a file, or from everything inside a folder.
    private static func removeQuarantine(at url: URL) {
        removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        guard let files = FileManager.default.enumerator(atPath: url.path) else { return }
        for case let file as String in files {
            removexattr(url.appendingPathComponent(file).path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
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
