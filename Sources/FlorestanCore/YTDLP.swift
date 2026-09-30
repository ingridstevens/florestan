import Foundation

/// Pure helpers for reading yt-dlp's output.
public enum YTDLP {
    /// Output of `yt-dlp --flat-playlist -J <playlist>`.
    public struct FlatPlaylist: Decodable, Sendable {
        public struct Entry: Decodable, Sendable {
            public var id: String
            public var title: String?
            public var channel: String?
            public var uploader: String?
            /// Seconds.
            public var duration: Double?
        }
        public var id: String?
        public var title: String?
        public var entries: [Entry]
    }

    public static func parsePlaylist(_ data: Data) throws -> FlatPlaylist {
        var playlist = try JSONDecoder().decode(FlatPlaylist.self, from: data)
        // YouTube Music album titles come back as "Album - Album"; the playlist name is enough.
        if let title = playlist.title, title.hasPrefix("Album - ") { playlist.title = String(title.dropFirst(8)) }
        return playlist
    }

    /// Prefix Florestan passes via `--progress-template "download:FLORESTAN %(…)s"`.
    public static let progressMarker = "FLORESTAN "

    public static var progressTemplate: String {
        "download:\(progressMarker)%(progress.downloaded_bytes)s %(progress.total_bytes,progress.total_bytes_estimate)s"
    }

    /// Returns download progress 0…1 from a progress line, or nil if the line isn't one.
    public static func progress(fromLine line: String) -> Double? {
        guard let range = line.range(of: progressMarker) else { return nil }
        let parts = line[range.upperBound...].split(separator: " ")
        guard parts.count == 2, let done = Double(parts[0]), let total = Double(parts[1]), total > 0 else { return nil }
        return min(max(done / total, 0), 1)
    }

    /// Why a Track failed, in words the user can act on.
    public enum Failure: Equatable, Sendable, Codable {
        case botCheck
        case ageRestricted
        case privateVideo
        case membersOnly
        case unavailable
        /// macOS blocks reading Safari's cookies without Full Disk Access.
        case safariNeedsFullDiskAccess
        /// The browser's cookie store couldn't be read or decrypted.
        case browserLoginUnreadable
        /// YouTube changed something; updating yt-dlp usually fixes it.
        case extractorBroken(String)
        case other(String)

        public var message: String {
            switch self {
            case .botCheck: "YouTube asked for a bot check. This network is probably blocked; try another network or turn on “Use my browser's YouTube login” in Settings."
            case .ageRestricted: "Age-restricted. Needs a signed-in YouTube account."
            case .privateVideo: "Private video"
            case .membersOnly: "Members-only video"
            case .unavailable: "Video unavailable"
            case .safariNeedsFullDiskAccess: "Florestan needs Full Disk Access to use your Safari login. Add Florestan.exe in System Settings › Privacy & Security › Full Disk Access, or pick another browser in Settings."
            case .browserLoginUnreadable: "Couldn't read your browser's YouTube login. Make sure you're signed in to YouTube there, and allow Keychain access when macOS asks."
            case .extractorBroken(let detail): "YouTube changed something yt-dlp relies on: \(detail)"
            case .other(let detail): detail
            }
        }

        /// Failures that retrying can't fix.
        public var isPermanent: Bool {
            switch self {
            case .ageRestricted, .privateVideo, .membersOnly, .unavailable, .botCheck, .safariNeedsFullDiskAccess, .browserLoginUnreadable: true
            case .extractorBroken, .other: false
            }
        }

        public var shouldUpgradeAndRetry: Bool {
            if case .extractorBroken = self { true } else { false }
        }
    }

    /// Classifies yt-dlp's stderr into a Failure.
    public static func classify(stderr: String) -> Failure {
        let lower = stderr.lowercased()
        if lower.contains("operation not permitted") && lower.contains("com.apple.safari") { return .safariNeedsFullDiskAccess }
        if lower.contains("failed to decrypt") || lower.contains("cannot decrypt") || lower.contains("could not find") && lower.contains("cookies database") {
            return .browserLoginUnreadable
        }
        if lower.contains("not a bot") { return .botCheck }
        if lower.contains("confirm your age") || lower.contains("age-restricted") { return .ageRestricted }
        if lower.contains("private video") { return .privateVideo }
        if lower.contains("members-only") || lower.contains("join this channel") { return .membersOnly }
        let lastError = stderr.split(separator: "\n").last(where: { $0.hasPrefix("ERROR:") })
            .map { String($0.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces) }
            ?? stderr.split(separator: "\n").last.map(String.init) ?? "yt-dlp failed"
        if lower.contains("video unavailable") || lower.contains("has been removed") { return .unavailable }
        let brokenSignals = ["unable to extract", "nsig extraction failed", "http error 403", "requested format is not available", "signature extraction failed"]
        if brokenSignals.contains(where: lower.contains) { return .extractorBroken(Self.stripVideoPrefix(lastError)) }
        return .other(Self.stripVideoPrefix(lastError))
    }

    /// "[youtube] abc123: Something" → "Something"
    static func stripVideoPrefix(_ s: String) -> String {
        s.replacingOccurrences(of: #"^\[[^\]]+\]\s*[\w-]+:\s*"#, with: "", options: .regularExpression)
    }
}
