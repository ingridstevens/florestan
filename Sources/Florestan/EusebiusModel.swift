import Foundation
import FoundationModels
import Observation

/// The feel a song has. Eusebius sorts songs into these, not by genre.
enum Mood: String, CaseIterable, Codable {
    case focus, lateNight, windDown, morningLift, workout, feelGood, melancholy, party
    case dreamy, romantic, roadTrip, rainyDay, dinner, cinematic

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
        case .dreamy: "Dreamy"
        case .romantic: "Romantic"
        case .roadTrip: "Road Trip"
        case .rainyDay: "Rainy Day"
        case .dinner: "Dinner"
        case .cinematic: "Cinematic"
        }
    }

    /// Also the hint the model gets for this Mood.
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
        case .dreamy: "Floating, atmospheric, far away."
        case .romantic: "Tender and intimate."
        case .roadTrip: "Open-road songs with momentum."
        case .rainyDay: "Cozy and grey, for staying in."
        case .dinner: "Elegant background for a meal."
        case .cinematic: "Grand, sweeping, dramatic."
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
        case .dreamy: "cloud"
        case .romantic: "heart"
        case .roadTrip: "car"
        case .rainyDay: "cloud.rain"
        case .dinner: "wineglass"
        case .cinematic: "film"
        }
    }
}

/// A Mood Playlist Eusebius proposes.
struct MoodSuggestion: Identifiable {
    var mood: Mood
    var tracks: [MusicLibrary.LibraryTrack]
    var id: Mood { mood }
    var playlistName: String { "\(mood.playlistName) · Eusebius" }
}

/// What the user thinks of a Mood Playlist.
enum MoodFeedback: String, Codable {
    /// Created in Apple Music and kept up to date on every run.
    case liked
    /// Never suggested again.
    case disliked
}

/// Reads the whole Apple Music library, finds each song's Moods on-device, and proposes Mood Playlists.
@MainActor @Observable
final class EusebiusModel {
    enum Phase: Equatable {
        case idle
        case readingLibrary
        case listening(done: Int, total: Int)
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var suggestions: [MoodSuggestion] = []
    private(set) var feedback: [Mood: MoodFeedback]
    /// Moods whose playlist is being created or updated right now.
    private(set) var syncing: Set<Mood> = []
    private(set) var lastError: String?
    private var work: Task<Void, Never>?

    /// Up to two Moods per song, keyed by Apple Music persistent ID, so later runs only listen to new songs.
    private var moods: [String: [Mood]]
    private var createdPlaylists: [Mood: String]
    private let storeURL = AppModel.supportFolder.appendingPathComponent("eusebius.json")

    private struct Store: Codable {
        var moods: [String: [Mood]] = [:]
        var playlists: [Mood: String] = [:]
        var feedback: [Mood: MoodFeedback] = [:]
    }

    static let minimumPlaylistSize = 5
    private static let batchSize = 25

    init() {
        let store = (try? Data(contentsOf: AppModel.supportFolder.appendingPathComponent("eusebius.json")))
            .flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
        moods = store.moods
        createdPlaylists = store.playlists
        feedback = store.feedback
    }

    var unavailableReason: String? { Self.modelUnavailableReason(for: "Eusebius") }

    /// Why the on-device model can't run, or nil when it can.
    static func modelUnavailableReason(for feature: String) -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled):
            "\(feature) uses Apple Intelligence, which is turned off. Turn it on in System Settings › Apple Intelligence & Siri."
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
        case .readingLibrary, .listening: true
        default: false
        }
    }

    var visibleSuggestions: [MoodSuggestion] { suggestions.filter { feedback[$0.mood] != .disliked } }
    var hiddenMoods: [Mood] { Mood.allCases.filter { feedback[$0] == .disliked } }
    var hasListenedBefore: Bool { !moods.isEmpty }

    /// Listens to songs it hasn't heard yet. With `everything`, forgets every earlier judgment and listens to the whole library again.
    func listen(everything: Bool = false) {
        work?.cancel()
        if everything { moods = [:] }
        work = Task { await runListen() }
    }

    func cancel() {
        work?.cancel()
        phase = suggestions.isEmpty ? .idle : .ready
    }

    func like(_ suggestion: MoodSuggestion) {
        feedback[suggestion.mood] = .liked
        save()
        Task { await sync(suggestion) }
    }

    func dislike(_ suggestion: MoodSuggestion) {
        feedback[suggestion.mood] = .disliked
        save()
    }

    func clearFeedback(_ mood: Mood) {
        feedback[mood] = nil
        save()
    }

    func isInAppleMusic(_ mood: Mood) -> Bool { createdPlaylists[mood] != nil && feedback[mood] == .liked }

    // MARK: - Listening

    private func runListen() async {
        phase = .readingLibrary
        lastError = nil
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

        let unheard = songs.filter { moods[$0.id] == nil }
        var done = songs.count - unheard.count
        phase = .listening(done: done, total: songs.count)
        for start in stride(from: 0, to: unheard.count, by: Self.batchSize) {
            if Task.isCancelled { return }
            let batch = Array(unheard[start..<min(start + Self.batchSize, unheard.count)])
            for (id, found) in await classify(batch) { moods[id] = found }
            done += batch.count
            phase = .listening(done: done, total: songs.count)
            save()
        }

        var byMood: [Mood: [MusicLibrary.LibraryTrack]] = [:]
        for song in songs {
            for mood in moods[song.id] ?? [] { byMood[mood, default: []].append(song) }
        }
        suggestions = Mood.allCases.compactMap { mood in
            guard let tracks = byMood[mood], tracks.count >= Self.minimumPlaylistSize else { return nil }
            return MoodSuggestion(mood: mood, tracks: tracks)
        }
        // Liked playlists follow the library: new songs join them on every run.
        for suggestion in suggestions where feedback[suggestion.mood] == .liked {
            await sync(suggestion)
        }
        phase = suggestions.isEmpty
            ? .failed("Eusebius didn't find enough songs for any mood. Each playlist needs at least \(Self.minimumPlaylistSize).")
            : .ready
    }

    /// Classifies a batch. If the model refuses or overflows, splits the batch and tries the halves; single songs that still fail are skipped.
    private func classify(_ batch: [MusicLibrary.LibraryTrack]) async -> [(String, [Mood])] {
        guard !batch.isEmpty else { return [] }
        let list = batch.enumerated().map { i, t in
            let genre = t.genre.isEmpty ? "" : " [\(t.genre)]"
            return "\(i + 1). \(t.artist) – \(t.name)\(genre)"
        }.joined(separator: "\n")
        let palette = Mood.allCases.map { "\($0.rawValue) (\($0.blurb.dropLast().lowercased()))" }.joined(separator: ", ")
        // Plain-text replies: guided generation (@Generable) needs a macro plugin that ships only with Xcode.
        let session = LanguageModelSession(instructions: """
            You sort songs into playlists by how they feel to listen to, not by genre. \
            Use what you know about each artist and song. For every numbered song, pick one or two moods from: \(palette).
            Reply with one line per song, formatted exactly as `<number>: <mood>` or `<number>: <mood>, <mood>`, \
            using only the mood words above. No other text.
            """)
        do {
            let response = try await session.respond(to: "Songs:\n\(list)")
            let parsed = Self.parseMoods(response.content).compactMap { number, found -> (String, [Mood])? in
                batch.indices.contains(number - 1) ? (batch[number - 1].id, found) : nil
            }
            if parsed.isEmpty && batch.count > 1 { throw CancellationError() }
            return parsed
        } catch {
            if Task.isCancelled || batch.count == 1 { return [] }
            let mid = batch.count / 2
            return await classify(Array(batch[..<mid])) + classify(Array(batch[mid...]))
        }
    }

    /// Reads lines like "12: lateNight, dreamy" (tolerating "12. Late night", bullets and stray text).
    static func parseMoods(_ text: String) -> [(Int, [Mood])] {
        let lookup = Dictionary(uniqueKeysWithValues: Mood.allCases.map { ($0.rawValue.lowercased(), $0) })
        return text.split(separator: "\n").compactMap { line in
            guard let match = line.firstMatch(of: #/(\d+)\s*[:.)=\-–]\s*\**\s*(.+)/#), let number = Int(match.1) else { return nil }
            let found = match.2.split(whereSeparator: { $0 == "," || $0 == "/" || $0 == "&" })
                .compactMap { lookup[$0.lowercased().filter(\.isLetter)] }
            let unique = found.reduce(into: [Mood]()) { if !$0.contains($1) { $0.append($1) } }
            return unique.isEmpty ? nil : (number, Array(unique.prefix(2)))
        }
    }

    // MARK: - Apple Music

    private func sync(_ suggestion: MoodSuggestion) async {
        syncing.insert(suggestion.mood)
        defer { syncing.remove(suggestion.mood) }
        do {
            let id = try await MusicLibrary.mirror(playlistNamed: suggestion.playlistName,
                                                   existingID: createdPlaylists[suggestion.mood],
                                                   trackIDs: suggestion.tracks.map(\.id))
            createdPlaylists[suggestion.mood] = id
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func save() {
        let store = Store(moods: moods, playlists: createdPlaylists, feedback: feedback)
        if let data = try? JSONEncoder().encode(store) { try? data.write(to: storeURL, options: .atomic) }
    }
}
