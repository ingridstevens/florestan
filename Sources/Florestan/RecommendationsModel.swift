import Foundation
import FlorestanCore
import FoundationModels
import Observation

/// A song Florestan proposes because YouTube relates it to songs already imported. See CONTEXT.md.
struct Recommendation: Identifiable, Codable, Hashable {
    var videoID: String
    var title: String
    var artist: String
    /// Title of the imported song it's related to.
    var because: String
    var id: String { videoID }
    var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")! }
    var url: String { "https://www.youtube.com/watch?v=\(videoID)" }
}

/// A song Apple Intelligence proposes on this Mac, without going online. Only a name until the user adds it.
struct IdeaRecommendation: Identifiable, Hashable {
    var artist: String
    var title: String
    var id: String { "\(artist.lowercased())|\(title.lowercased())" }
    var query: String { "\(artist) \(title)" }
    var searchURL: URL {
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [.init(name: "search_query", value: query)]
        return c.url!
    }
}

/// Builds Recommendations from YouTube's "Mix" of each recently imported song,
/// or, offline, from Apple Intelligence's knowledge of music.
@MainActor @Observable
final class RecommendationsModel {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var items: [Recommendation] = []
    private(set) var added: Set<String> = []

    // Apple Intelligence (offline) recommendations.
    private(set) var ideaPhase: Phase = .idle
    private(set) var ideas: [IdeaRecommendation] = []
    /// Ideas being looked up on YouTube, and ones already queued.
    private(set) var resolving: Set<String> = []
    private(set) var ideasAdded: Set<String> = []
    private(set) var ideaErrors: [String: String] = [:]
    /// The YouTube video each added Idea turned out to be.
    private(set) var ideaVideoIDs: [String: String] = [:]
    /// How many suggestions were left out because the song is already in Apple Music.
    private(set) var ownedCount = 0
    private(set) var ownedIdeasCount = 0
    /// Why adding a Recommendation didn't start, by video ID.
    private(set) var addErrors: [String: String] = [:]
    private var matcherCache: (matcher: LibraryMatcher, songCount: Int, builtAt: Date)?

    private var dismissed: Set<String>
    private var lastRefresh: Date?
    private let storeURL = AppModel.supportFolder.appendingPathComponent("recommendations.json")

    private struct Store: Codable {
        var items: [Recommendation] = []
        var dismissed: Set<String> = []
        var lastRefresh: Date?
    }

    private static let seedCount = 6
    private static let perSeed = 25
    private static let maxItems = 24

    init() {
        let store = (try? Data(contentsOf: storeURL)).flatMap { try? JSONDecoder.florestan.decode(Store.self, from: $0) } ?? Store()
        items = store.items
        dismissed = store.dismissed
        lastRefresh = store.lastRefresh
        if !items.isEmpty { phase = .ready }
    }

    var isStale: Bool {
        guard let lastRefresh else { return true }
        return Date.now.timeIntervalSince(lastRefresh) > 12 * 60 * 60
    }

    func refreshIfStale(using model: AppModel) {
        if (isStale || items.isEmpty) && phase != .loading && !model.librarySongs.isEmpty {
            refresh(using: model)
        } else {
            pruneOwned(using: model)
        }
    }

    /// Drops saved suggestions that have since turned up in Apple Music (except ones just added here, which show their status).
    private func pruneOwned(using model: AppModel) {
        guard !items.isEmpty else { return }
        Task {
            let owned = await libraryMatcher(using: model)
            let before = items.count
            items.removeAll { !added.contains($0.videoID) && owned.contains(title: $0.title, artist: $0.artist) }
            if items.count != before {
                ownedCount += before - items.count
                save()
            }
        }
    }

    func refresh(using model: AppModel) {
        guard phase != .loading else { return }
        let seeds = Array(model.librarySongs.prefix(Self.seedCount))
        guard !seeds.isEmpty else { return }
        phase = .loading
        let downloader = Downloader(cookieBrowser: model.settings.useBrowserLogin ? model.settings.cookieBrowser : nil)
        let known = Set(model.librarySongs.map(\.videoID))
        Task {
            async let ownedLibrary = libraryMatcher(using: model)
            // Seed video → its Mix entries, fetched three at a time.
            var mixes: [(LedgerEntry, [YTDLP.FlatPlaylist.Entry])] = []
            await withTaskGroup(of: (LedgerEntry, [YTDLP.FlatPlaylist.Entry]).self) { group in
                var pending = seeds.makeIterator()
                func addNext() {
                    guard let seed = pending.next() else { return }
                    group.addTask {
                        let mix = Link.playlist(id: "RD\(seed.videoID)",
                                                url: URL(string: "https://www.youtube.com/watch?v=\(seed.videoID)&list=RD\(seed.videoID)")!)
                        let entries = (try? await downloader.fetchPlaylist(mix, limit: Self.perSeed))?.entries ?? []
                        return (seed, entries)
                    }
                }
                for _ in 0..<3 { addNext() }
                while let result = await group.next() {
                    mixes.append(result)
                    addNext()
                }
            }

            // Songs that show up in several Mixes rank first; official "- Topic" audio gets a nudge.
            var scores: [String: Double] = [:]
            var info: [String: Recommendation] = [:]
            for (seed, entries) in mixes {
                for (position, entry) in entries.enumerated() {
                    let id = entry.id
                    guard !known.contains(id), !dismissed.contains(id), let title = entry.title else { continue }
                    if let d = entry.duration, d < 60 || d > 15 * 60 { continue }
                    let channel = entry.channel ?? entry.uploader ?? ""
                    let isTopic = channel.hasSuffix(" - Topic")
                    scores[id, default: 0] += 10 + (isTopic ? 3 : 0) - Double(position) / 5
                    if info[id] == nil {
                        let meta = TrackMetadata(from: VideoInfo(id: id, title: title, channel: channel))
                        info[id] = Recommendation(videoID: id, title: meta.title, artist: meta.artist, because: seed.metadata.title)
                    }
                }
            }
            // Leave out songs already in Apple Music under a slightly different title or credit.
            // Only count the ones that would otherwise have been in the running.
            let owned = await ownedLibrary
            let candidates = scores.sorted { $0.value > $1.value }.compactMap { info[$0.key] }
            var fresh: [Recommendation] = []
            var ownedSeen = 0
            for candidate in candidates where fresh.count < Self.maxItems * 2 {
                if owned.contains(title: candidate.title, artist: candidate.artist) { ownedSeen += 1 } else { fresh.append(candidate) }
            }
            // Take turns between seed songs so one artist doesn't fill the whole list.
            let bySeed = Dictionary(grouping: fresh, by: \.because)
            var queues = seeds.compactMap { bySeed[$0.metadata.title] }
            var ranked: [Recommendation] = []
            while ranked.count < Self.maxItems, queues.contains(where: { !$0.isEmpty }) {
                for i in queues.indices where !queues[i].isEmpty && ranked.count < Self.maxItems {
                    let next = queues[i].removeFirst()
                    if !ranked.contains(next) { ranked.append(next) }
                }
            }
            if ranked.isEmpty {
                phase = mixes.allSatisfy({ $0.1.isEmpty })
                    ? .failed("Couldn't reach YouTube. If a VPN is on, turn it off and refresh.")
                    : .failed("No new suggestions right now. Download a few more songs and refresh.")
            } else {
                items = ranked
                ownedCount = ownedSeen
                lastRefresh = .now
                phase = .ready
            }
            save()
        }
    }

    func add(_ item: Recommendation, using model: AppModel) {
        addErrors[item.videoID] = nil
        if let error = Self.startDownload(item.videoID, using: model) {
            addErrors[item.videoID] = error
        } else {
            added.insert(item.videoID)
        }
    }

    /// Queues a song, or says why it couldn't be. A song already imported counts as added.
    private static func startDownload(_ videoID: String, using model: AppModel) -> String? {
        if model.isInLibrary(videoID) { return nil }
        switch model.submit("https://www.youtube.com/watch?v=\(videoID)") {
        case .queued, .alreadyQueued: return nil
        case .toolsMissing: return "Install yt-dlp and ffmpeg first (see Downloads)."
        case .notALink: return "Couldn't make a YouTube link for this song."
        }
    }

    func dismiss(_ item: Recommendation) {
        dismissed.insert(item.videoID)
        items.removeAll { $0.videoID == item.videoID }
        save()
    }

    var ideasUnavailableReason: String? { EusebiusModel.modelUnavailableReason(for: "Offline suggestions") }

    /// When the current Idea request started, for the elapsed-time display.
    private(set) var ideasStartedAt: Date?

    /// Asks the on-device model for songs like the ones already imported. Works without a network connection.
    func suggestIdeas(using model: AppModel) {
        guard ideaPhase != .loading, ideasUnavailableReason == nil else { return }
        var seeds = Self.seedLines(from: model.librarySongs)
        guard !seeds.isEmpty else { return }
        ideaPhase = .loading
        ideasStartedAt = .now
        Task {
            async let ownedLibrary = libraryMatcher(using: model)
            var reply: String?
            var failure: String?
            // The on-device model has a small context window (about 4,000 tokens for prompt and answer together).
            // If the song list still doesn't fit, try again with half of it.
            while reply == nil && failure == nil {
                do {
                    reply = try await Self.askForIdeas(seeds)
                } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                    if seeds.count <= 3 { failure = "Apple Intelligence ran out of room. Try again." } else { seeds = Array(seeds.prefix(seeds.count / 2)) }
                } catch {
                    failure = "Apple Intelligence couldn't make suggestions: \(error.localizedDescription)"
                }
            }
            let owned = await ownedLibrary
            if let reply {
                let all = Self.parseIdeas(reply)
                let parsed = all.filter { !owned.contains(title: $0.title, artist: $0.artist) }
                ownedIdeasCount = all.count - parsed.count
                ideas = parsed
                ideaPhase = parsed.isEmpty ? .failed("Apple Intelligence didn't come up with any new songs. Try again.") : .ready
            } else {
                ideaPhase = .failed(failure ?? "Apple Intelligence couldn't make suggestions.")
            }
            ideasStartedAt = nil
        }
    }

    private static func askForIdeas(_ seeds: [String]) async throws -> String {
        let session = LanguageModelSession(instructions: """
            You recommend music. Suggest real, existing songs that a listener with these songs would enjoy: \
            similar in feel, era or style. Each suggestion must be a different song, mostly by other artists, \
            and none of the listener's songs. Reply with one song per line, formatted exactly as `Artist – Title`. \
            No numbering, no other text.
            """)
        let response = try await session.respond(to: "My songs:\n\(seeds.joined(separator: "\n"))\n\nSuggest 12 songs.")
        return response.content
    }

    /// A short, varied sample of the library: at most three songs per artist, lead artist only, titles without extras,
    /// capped so the prompt stays well inside the on-device model's context window.
    static func seedLines(from songs: [LedgerEntry], characterBudget: Int = 1800) -> [String] {
        var byArtist: [String: [String]] = [:]
        var artistOrder: [String] = []
        for song in songs {
            let lead = song.metadata.artist.components(separatedBy: ", ").first ?? song.metadata.artist
            var title = song.metadata.title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            if title.count > 50 { title = String(title.prefix(50)) }
            if byArtist[lead] == nil { artistOrder.append(lead) }
            if byArtist[lead, default: []].count < 3 { byArtist[lead, default: []].append("\(lead) – \(title)") }
        }
        var lines: [String] = []
        var used = 0
        for round in 0..<3 {
            for artist in artistOrder {
                guard let songs = byArtist[artist], songs.indices.contains(round) else { continue }
                let line = songs[round]
                if used + line.count > characterBudget { return lines }
                lines.append(line)
                used += line.count + 1
            }
        }
        return lines
    }

    /// Reads lines like "Glass Animals – Heat Waves", tolerating numbering, bullets and quotes.
    static func parseIdeas(_ text: String) -> [IdeaRecommendation] {
        var seen = Set<String>()
        return text.split(separator: "\n").compactMap { raw -> IdeaRecommendation? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            line = line.replacingOccurrences(of: #"^(\d+[.)]|[-*•])\s*"#, with: "", options: .regularExpression)
            for separator in [" – ", " — ", " - "] {
                let parts = line.components(separatedBy: separator)
                if parts.count >= 2 {
                    let artist = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"“”* "))
                    let title = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”* "))
                    guard !artist.isEmpty, !title.isEmpty else { return nil }
                    let idea = IdeaRecommendation(artist: artist, title: title)
                    return seen.insert(idea.id).inserted ? idea : nil
                }
            }
            return nil
        }
    }

    /// Finds the idea on YouTube and queues the top result.
    func add(_ idea: IdeaRecommendation, using model: AppModel) {
        guard !resolving.contains(idea.id) else { return }
        resolving.insert(idea.id)
        ideaErrors[idea.id] = nil
        let downloader = Downloader(cookieBrowser: model.settings.useBrowserLogin ? model.settings.cookieBrowser : nil)
        Task {
            defer { resolving.remove(idea.id) }
            do {
                guard let videoID = try await downloader.searchTopVideo(idea.query) else {
                    ideaErrors[idea.id] = "Not found on YouTube"
                    return
                }
                ideaVideoIDs[idea.id] = videoID
                if let error = Self.startDownload(videoID, using: model) {
                    ideaErrors[idea.id] = error
                } else {
                    ideasAdded.insert(idea.id)
                }
            } catch let error as DownloadFailure {
                ideaErrors[idea.id] = error.failure.message
            } catch {
                ideaErrors[idea.id] = "Couldn't search YouTube. Check your connection."
            }
        }
    }

    func dismiss(_ idea: IdeaRecommendation) {
        ideas.removeAll { $0.id == idea.id }
    }

    /// Every song in Apple Music plus everything Florestan imported. Built off the main thread, and reused for
    /// ten minutes or until Florestan imports something, because reading a big library takes a while and holds up imports.
    private func libraryMatcher(using model: AppModel) async -> LibraryMatcher {
        if let cache = matcherCache, cache.songCount == model.librarySongs.count,
           Date.now.timeIntervalSince(cache.builtAt) < 10 * 60 {
            return cache.matcher
        }
        let imported = model.librarySongs.map { ($0.metadata.title, $0.metadata.artist) }
        let built = await Task.detached(priority: .utility) { () -> LibraryMatcher in
            var matcher = LibraryMatcher(songs: imported)
            if let songs = try? await MusicLibrary.allSongs() {
                for song in songs { matcher.add(title: song.name, artist: song.artist) }
            }
            return matcher
        }.value
        matcherCache = (built, model.librarySongs.count, .now)
        return built
    }

    private func save() {
        let store = Store(items: items, dismissed: dismissed, lastRefresh: lastRefresh)
        if let data = try? JSONEncoder.florestan.encode(store) { try? data.write(to: storeURL, options: .atomic) }
    }
}
