import Foundation
import FoundationModels
import Observation

/// The feel a song has. Eusebius sorts songs into these, not by genre.
enum Mood: String, CaseIterable, Codable {
    case focus, lateNight, windDown, morningLift, workout, feelGood, melancholy, party

    var playlistName: String {
        switch self {
        case .focus: "Focus"
        case .lateNight: "Late Night"
        case .windDown: "Wind Down"
        case .morningLift: "Morning Lift"
        case .workout: "Workout"
        case .feelGood: "Feel Good"
        case .melancholy: "Melancholy"
        case .party: "Party"
        }
    }

    var blurb: String {
        switch self {
        case .focus: "Steady, unobtrusive music for concentrating."
        case .lateNight: "Moody, nocturnal, a little hazy."
        case .windDown: "Soft and slow, for the end of the day."
        case .morningLift: "Bright and easy, for getting going."
        case .workout: "Driving, high-energy tracks."
        case .feelGood: "Warm, upbeat, sing-along."
        case .melancholy: "Wistful, bittersweet, reflective."
        case .party: "Loud, danceable, made for a crowd."
        }
    }

    var symbol: String {
        switch self {
        case .focus: "brain.head.profile"
        case .lateNight: "moon"
        case .windDown: "cloud.moon"
        case .morningLift: "sunrise"
        case .workout: "figure.run"
        case .feelGood: "sun.max"
        case .melancholy: "cloud.drizzle"
        case .party: "sparkles"
        }
    }
}

/// A mood playlist Eusebius proposes. The user ticks the ones to create.
struct MoodSuggestion: Identifiable {
    var mood: Mood
    var tracks: [MusicLibrary.LibraryTrack]
    var selected = true
    var id: Mood { mood }
    var playlistName: String { "\(mood.playlistName) · Eusebius" }
}

/// Reads the whole Apple Music library, classifies each song's mood on-device, and creates mood playlists.
@MainActor @Observable
final class EusebiusModel {
    enum Phase: Equatable {
        case idle
        case readingLibrary
        case listening(done: Int, total: Int)
        case suggestions
        case creating
        case created(Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var suggestions: [MoodSuggestion] = []
    private var work: Task<Void, Never>?

    /// Classifications persist so later runs only look at new songs. Keyed by Apple Music persistent ID.
    private var cache: [String: Mood]
    private var createdPlaylists: [String: String]
    private let cacheURL = AppModel.supportFolder.appendingPathComponent("eusebius.json")

    private struct Store: Codable {
        var moods: [String: Mood] = [:]
        var playlists: [String: String] = [:]
    }

    static let minimumPlaylistSize = 5
    private static let batchSize = 30

    init() {
        let store = (try? Data(contentsOf: AppModel.supportFolder.appendingPathComponent("eusebius.json")))
            .flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
        cache = store.moods
        createdPlaylists = store.playlists
    }

    /// Why the on-device model can't run, or nil when it can.
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled):
            "Eusebius uses Apple Intelligence, which is turned off. Turn it on in System Settings › Apple Intelligence & Siri."
        case .unavailable(.modelNotReady):
            "Apple Intelligence is still downloading its model. Try again in a few minutes."
        case .unavailable(.deviceNotEligible):
            "This Mac doesn't support Apple Intelligence."
        case .unavailable:
            "Apple Intelligence isn't available right now."
        }
    }

    var isWorking: Bool {
        switch phase {
        case .readingLibrary, .listening, .creating: true
        default: false
        }
    }

    func suggest() {
        work?.cancel()
        work = Task { await runSuggest() }
    }

    func cancel() {
        work?.cancel()
        phase = suggestions.isEmpty ? .idle : .suggestions
    }

    private func runSuggest() async {
        phase = .readingLibrary
        let songs: [MusicLibrary.LibraryTrack]
        do {
            songs = try await MusicLibrary.allSongs()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        guard !songs.isEmpty else {
            phase = .failed("Your Apple Music library has no songs yet.")
            return
        }

        let unknown = songs.filter { cache[$0.id] == nil }
        var done = songs.count - unknown.count
        phase = .listening(done: done, total: songs.count)
        for start in stride(from: 0, to: unknown.count, by: Self.batchSize) {
            if Task.isCancelled { return }
            let batch = Array(unknown[start..<min(start + Self.batchSize, unknown.count)])
            for (id, mood) in await classify(batch) { cache[id] = mood }
            done += batch.count
            phase = .listening(done: done, total: songs.count)
            save()
        }

        let byMood = Dictionary(grouping: songs.filter { cache[$0.id] != nil }, by: { cache[$0.id]! })
        suggestions = Mood.allCases.compactMap { mood in
            guard let tracks = byMood[mood], tracks.count >= Self.minimumPlaylistSize else { return nil }
            return MoodSuggestion(mood: mood, tracks: tracks)
        }
        phase = suggestions.isEmpty
            ? .failed("Eusebius didn't find enough songs for any mood. Each playlist needs at least \(Self.minimumPlaylistSize).")
            : .suggestions
    }

    /// Classifies a batch. If the model refuses or overflows, splits the batch and tries the halves; single songs that still fail are skipped.
    private func classify(_ batch: [MusicLibrary.LibraryTrack]) async -> [(String, Mood)] {
        guard !batch.isEmpty else { return [] }
        let list = batch.enumerated().map { i, t in
            let genre = t.genre.isEmpty ? "" : " [\(t.genre)]"
            return "\(i + 1). \(t.artist) – \(t.name)\(genre)"
        }.joined(separator: "\n")
        let moodWords = Mood.allCases.map(\.rawValue).joined(separator: ", ")
        // Plain-text replies: guided generation (@Generable) needs a macro plugin that ships only with Xcode.
        let session = LanguageModelSession(instructions: """
            You sort songs into playlists by how they feel to listen to, not by genre. \
            Use what you know about each artist and song. For every numbered song, pick the single best mood: \
            focus (steady, unobtrusive), lateNight (moody, nocturnal), windDown (soft, slow), \
            morningLift (bright, easy), workout (driving, high energy), feelGood (warm, upbeat), \
            melancholy (wistful, sad), party (loud, danceable).
            Reply with one line per song, formatted exactly as `<number>: <mood>`, using only these words: \(moodWords). \
            No other text.
            """)
        do {
            let response = try await session.respond(to: "Songs:\n\(list)")
            let parsed = Self.parseMoods(response.content)
            let result = parsed.compactMap { number, mood -> (String, Mood)? in
                batch.indices.contains(number - 1) ? (batch[number - 1].id, mood) : nil
            }
            if result.isEmpty && batch.count > 1 { throw CancellationError() }
            return result
        } catch {
            if Task.isCancelled || batch.count == 1 { return [] }
            let mid = batch.count / 2
            return await classify(Array(batch[..<mid])) + classify(Array(batch[mid...]))
        }
    }

    /// Reads lines like "12: lateNight" (tolerating "12. Late night", bullets and stray text).
    static func parseMoods(_ text: String) -> [(Int, Mood)] {
        let lookup = Dictionary(uniqueKeysWithValues: Mood.allCases.map { ($0.rawValue.lowercased(), $0) })
        return text.split(separator: "\n").compactMap { line in
            guard let match = line.firstMatch(of: #/(\d+)\s*[:.)=\-–]\s*\**\s*([A-Za-z][A-Za-z ]*[A-Za-z])/#),
                  let number = Int(match.1) else { return nil }
            let word = match.2.lowercased().replacingOccurrences(of: " ", with: "")
            return lookup[word].map { (number, $0) }
        }
    }

    func createSelected() {
        work = Task {
            phase = .creating
            var count = 0
            for suggestion in suggestions where suggestion.selected {
                do {
                    let id = try await MusicLibrary.mirror(playlistNamed: suggestion.playlistName,
                                                           existingID: createdPlaylists[suggestion.mood.rawValue],
                                                           trackIDs: suggestion.tracks.map(\.id))
                    createdPlaylists[suggestion.mood.rawValue] = id
                    count += 1
                } catch {
                    phase = .failed(error.localizedDescription)
                    save()
                    return
                }
            }
            save()
            phase = .created(count)
        }
    }

    private func save() {
        let store = Store(moods: cache, playlists: createdPlaylists)
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: cacheURL, options: .atomic) }
    }
}
