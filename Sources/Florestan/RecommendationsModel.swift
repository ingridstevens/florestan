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
        if (isStale || items.isEmpty) && phase != .loading && !model.librarySongs.isEmpty { refresh(using: model) }
    }

    func refresh(using model: AppModel) {
        guard phase != .loading else { return }
        let seeds = Array(model.librarySongs.prefix(Self.seedCount))
        guard !seeds.isEmpty else { return }
        phase = .loading
        let downloader = Downloader(cookieBrowser: model.settings.useBrowserLogin ? model.settings.cookieBrowser : nil)
        let known = Set(model.librarySongs.map(\.videoID))
        Task {
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
            // Take turns between seed songs so one artist doesn't fill the whole list.
            let bySeed = Dictionary(grouping: scores.sorted { $0.value > $1.value }.compactMap { info[$0.key] }, by: \.because)
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
                lastRefresh = .now
                phase = .ready
            }
            save()
        }
    }

    func add(_ item: Recommendation, using model: AppModel) {
        let result = model.submit(item.url)
        if result == .queued || result == .alreadyQueued {
            added.insert(item.videoID)
        }
    }

    func dismiss(_ item: Recommendation) {
        dismissed.insert(item.videoID)
        items.removeAll { $0.videoID == item.videoID }
        save()
    }

    var ideasUnavailableReason: String? { EusebiusModel.modelUnavailableReason(for: "Offline suggestions") }

    /// Asks the on-device model for songs like the ones already imported. Works without a network connection.
    func suggestIdeas(using model: AppModel) {
        guard ideaPhase != .loading, ideasUnavailableReason == nil else { return }
        let seeds = model.librarySongs.prefix(40).map { "\($0.metadata.artist) – \($0.metadata.title)" }
        guard !seeds.isEmpty else { return }
        let owned = Set(model.librarySongs.map { $0.metadata.title.lowercased() })
        ideaPhase = .loading
        Task {
            let session = LanguageModelSession(instructions: """
                You recommend music. Suggest real, existing songs that a listener with these songs would enjoy: \
                similar in feel, era or style, including other artists. Never repeat the listener's songs. \
                Reply with one song per line, formatted exactly as `Artist – Title`. No numbering, no other text.
                """)
            do {
                let response = try await session.respond(to: "My songs:\n\(seeds.joined(separator: "\n"))\n\nSuggest 15 songs.")
                let parsed = Self.parseIdeas(response.content).filter { !owned.contains($0.title.lowercased()) }
                ideas = parsed
                ideaPhase = parsed.isEmpty ? .failed("Apple Intelligence didn't come up with any songs. Try again.") : .ready
            } catch {
                ideaPhase = .failed("Apple Intelligence couldn't make suggestions: \(error.localizedDescription)")
            }
        }
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
                let result = model.submit("https://www.youtube.com/watch?v=\(videoID)")
                if result == .queued || result == .alreadyQueued { ideasAdded.insert(idea.id) }
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

    private func save() {
        let store = Store(items: items, dismissed: dismissed, lastRefresh: lastRefresh)
        if let data = try? JSONEncoder.florestan.encode(store) { try? data.write(to: storeURL, options: .atomic) }
    }
}
