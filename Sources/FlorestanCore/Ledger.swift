import Foundation

/// One song Florestan has imported.
public struct LedgerEntry: Codable, Equatable, Sendable, Identifiable {
    public var videoID: String
    public var metadata: TrackMetadata
    /// Apple Music's persistent ID for the imported track.
    public var musicTrackID: String
    public var importedAt: Date

    public var id: String { videoID }

    public init(videoID: String, metadata: TrackMetadata, musicTrackID: String, importedAt: Date = .now) {
        self.videoID = videoID; self.metadata = metadata; self.musicTrackID = musicTrackID; self.importedAt = importedAt
    }
}

/// Florestan's record of every video already imported, plus which Apple Music playlist mirrors which YouTube playlist.
public struct Ledger: Codable, Equatable, Sendable {
    public var songs: [String: LedgerEntry] = [:]
    /// YouTube playlist ID → Apple Music playlist persistent ID.
    public var mirroredPlaylists: [String: String] = [:]
    /// YouTube playlist ID → videos the user took out of its Mirrored Playlist. They're skipped next time too.
    public var removedFromPlaylists: [String: Set<String>] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey { case songs, mirroredPlaylists, removedFromPlaylists }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        songs = try c.decodeIfPresent([String: LedgerEntry].self, forKey: .songs) ?? [:]
        mirroredPlaylists = try c.decodeIfPresent([String: String].self, forKey: .mirroredPlaylists) ?? [:]
        removedFromPlaylists = try c.decodeIfPresent([String: Set<String>].self, forKey: .removedFromPlaylists) ?? [:]
    }
}

/// Loads and saves the Ledger as JSON. All access is serialized.
public actor LedgerStore {
    private let fileURL: URL
    private var ledger: Ledger

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.florestan.decode(Ledger.self, from: data) {
            ledger = decoded
        } else {
            ledger = Ledger()
        }
    }

    public var snapshot: Ledger { ledger }

    public func contains(_ videoID: String) -> Bool { ledger.songs[videoID] != nil }

    public func entry(for videoID: String) -> LedgerEntry? { ledger.songs[videoID] }

    public func record(_ entry: LedgerEntry) throws {
        ledger.songs[entry.videoID] = entry
        try save()
    }

    public func forget(_ videoID: String) throws {
        ledger.songs[videoID] = nil
        try save()
    }

    public func mirroredPlaylist(for youtubePlaylistID: String) -> String? {
        ledger.mirroredPlaylists[youtubePlaylistID]
    }

    public func setMirroredPlaylist(_ musicPlaylistID: String, for youtubePlaylistID: String) throws {
        ledger.mirroredPlaylists[youtubePlaylistID] = musicPlaylistID
        try save()
    }

    public func removedVideos(from youtubePlaylistID: String) -> Set<String> {
        ledger.removedFromPlaylists[youtubePlaylistID] ?? []
    }

    public func setRemoved(_ removed: Bool, videoID: String, from youtubePlaylistID: String) throws {
        if removed {
            ledger.removedFromPlaylists[youtubePlaylistID, default: []].insert(videoID)
        } else {
            ledger.removedFromPlaylists[youtubePlaylistID]?.remove(videoID)
        }
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.florestan.encode(ledger).write(to: fileURL, options: .atomic)
    }
}

extension JSONEncoder {
    public static var florestan: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    public static var florestan: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
