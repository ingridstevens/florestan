import Foundation
import FlorestanCore

/// Browsers yt-dlp can borrow a YouTube login from.
enum CookieBrowser: String, CaseIterable, Identifiable, Codable {
    case safari, chrome, firefox, brave, edge
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .brave: "Brave"
        case .edge: "Edge"
        }
    }
}

struct DownloadFailure: Error {
    var failure: YTDLP.Failure
}

/// Everything Florestan asks of yt-dlp and Homebrew.
struct Downloader: Sendable {
    var cookieBrowser: CookieBrowser?

    static var ytdlp: URL? { Shell.locate("yt-dlp") }
    static var ffmpeg: URL? { Shell.locate("ffmpeg") }
    static var brew: URL? { Shell.locate("brew") }

    static var toolsInstalled: Bool { ytdlp != nil && ffmpeg != nil }

    static func ytdlpVersion() async -> String? {
        guard let ytdlp else { return nil }
        let result = try? await Shell.run(ytdlp, ["--version"])
        return result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    /// `brew upgrade yt-dlp`. Returns true if it ran without error.
    @discardableResult
    static func upgradeYTDLP() async -> Bool {
        guard let brew else { return false }
        let result = try? await Shell.run(brew, ["upgrade", "yt-dlp"])
        return result?.succeeded ?? false
    }

    /// Title and channel from YouTube's oEmbed endpoint: fast, and usually works even when yt-dlp is blocked.
    static func quickInfo(videoID: String) async -> (title: String, author: String)? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [.init(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"), .init(name: "format", value: "json")]
        struct OEmbed: Decodable { var title: String; var author_name: String? }
        guard let (data, response) = try? await URLSession.shared.data(from: components.url!),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let info = try? JSONDecoder().decode(OEmbed.self, from: data) else { return nil }
        return (info.title, info.author_name ?? "")
    }

    private var commonArguments: [String] {
        var args = ["--ignore-config", "--no-warnings"]
        if let cookieBrowser { args += ["--cookies-from-browser", cookieBrowser.rawValue] }
        return args
    }

    /// Lists a playlist's entries without downloading anything.
    func fetchPlaylist(_ link: Link) async throws -> YTDLP.FlatPlaylist {
        guard let ytdlp = Self.ytdlp else { throw DownloadFailure(failure: .other("yt-dlp isn't installed")) }
        let result = try await Shell.run(ytdlp, commonArguments + ["--flat-playlist", "-J", link.url.absoluteString])
        guard result.succeeded else { throw DownloadFailure(failure: YTDLP.classify(stderr: result.stderr)) }
        do {
            return try YTDLP.parsePlaylist(Data(result.stdout.utf8))
        } catch {
            throw DownloadFailure(failure: .other("Couldn't read the playlist from YouTube."))
        }
    }

    struct Downloaded {
        var file: URL
        var info: VideoInfo
    }

    /// Downloads one video's audio as M4A with square cover art into `directory`.
    func downloadAudio(videoID: String, into directory: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> Downloaded {
        guard let ytdlp = Self.ytdlp, let ffmpeg = Self.ffmpeg else {
            throw DownloadFailure(failure: .other("yt-dlp or ffmpeg isn't installed"))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let squareCrop = #"ThumbnailsConvertor:-qmin 1 -q:v 1 -vf crop="'if(gt(ih,iw),iw,ih)':'if(gt(iw,ih),ih,iw)'""#
        let args = commonArguments + [
            "--no-playlist",
            "--ffmpeg-location", ffmpeg.deletingLastPathComponent().path,
            "-f", "bestaudio[ext=m4a]/bestaudio/best",
            "-x", "--audio-format", "m4a", "--audio-quality", "0",
            "--embed-thumbnail", "--convert-thumbnails", "jpg", "--ppa", squareCrop,
            "--embed-metadata",
            "--write-info-json",
            "--newline", "--progress", "--progress-template", YTDLP.progressTemplate,
            "-o", directory.appendingPathComponent("%(id)s.%(ext)s").path,
            "https://www.youtube.com/watch?v=\(videoID)",
        ]
        let result = try await Shell.run(ytdlp, args) { line in
            if let p = YTDLP.progress(fromLine: line) { onProgress(p) }
        }
        let file = directory.appendingPathComponent("\(videoID).m4a")
        let infoFile = directory.appendingPathComponent("\(videoID).info.json")
        defer { try? FileManager.default.removeItem(at: infoFile) }

        guard result.succeeded, FileManager.default.fileExists(atPath: file.path) else {
            throw DownloadFailure(failure: YTDLP.classify(stderr: result.stderr))
        }
        let info = (try? Data(contentsOf: infoFile)).flatMap { try? JSONDecoder().decode(VideoInfo.self, from: $0) }
            ?? VideoInfo(id: videoID, title: videoID)
        return Downloaded(file: file, info: info)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
