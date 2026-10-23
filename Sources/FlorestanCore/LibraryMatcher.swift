import Foundation

/// Answers "do I already have this song?" loosely: titles are compared after stripping case, accents, punctuation
/// and extras like "(Official Video)", "(feat. …)" or "- Remastered 2011", and artists only need to overlap.
public struct LibraryMatcher: Sendable {
    /// Normalized title → artist-name sets of the songs with that title.
    private var byTitle: [String: [Set<String>]] = [:]
    /// Artist name → normalized titles by that artist, for looser word-by-word matching.
    private var byArtist: [String: [String]] = [:]

    /// Words that mark another version of the same song rather than a different song.
    static let versionWords: Set<Substring> = [
        "slowed", "reverb", "sped", "up", "remix", "remastered", "remaster", "acoustic", "live", "version",
        "edit", "radio", "extended", "instrumental", "demo", "mono", "stereo", "mix", "original", "explicit", "clean",
    ]

    public init(songs: [(title: String, artist: String)]) {
        for song in songs { add(title: song.title, artist: song.artist) }
    }

    public init() {}

    public init(_ songs: [(title: String, artist: String)]) {
        self.init(songs: songs)
    }

    public var isEmpty: Bool { byTitle.isEmpty }

    public mutating func add(title: String, artist: String) {
        let key = Self.normalizeTitle(title)
        guard !key.isEmpty else { return }
        let names = Self.artistNames(artist)
        byTitle[key, default: []].append(names)
        for name in names { byArtist[name, default: []].append(key) }
    }

    public func contains(title: String, artist: String) -> Bool {
        let key = Self.normalizeTitle(title)
        guard !key.isEmpty else { return false }
        let names = Self.artistNames(artist)

        if let candidates = byTitle[key], candidates.contains(where: { Self.overlap($0, names) }) { return true }
        // Same artist, and one title is the other plus version words ("heat waves" ~ "heat waves slowed").
        for name in names {
            for other in byArtist[name] ?? [] where Self.isVersion(of: key, other) { return true }
        }
        return false
    }

    /// True when `candidate` is a title for the same recording as `original`, as when looking for another upload
    /// of a song. Stricter than `contains`: the candidate may drop or add a remaster note, a year or a "feat." credit,
    /// but not words like "Piano Version" or "Live" that make it a different recording.
    public static func isSameSong(_ candidate: String, as original: String) -> Bool {
        let key = normalizeTitle(original)
        guard !key.isEmpty, normalizeTitle(candidate) == key else { return false }
        let added = extraWords(candidate).subtracting(extraWords(original))
        return added.allSatisfy { harmlessExtras.contains($0) || $0.allSatisfy(\.isNumber) }
    }

    /// True when two artist credits share an artist ("Cash Cash" and "Cash Cash, Bebe Rexha").
    public static func sameArtist(_ a: String, _ b: String) -> Bool {
        overlap(artistNames(a), artistNames(b))
    }

    static let harmlessExtras: Set<String> = ["remaster", "remastered", "explicit"]

    /// Words of a title that `normalizeTitle` strips, apart from a "feat." credit.
    private static func extraWords(_ title: String) -> Set<String> {
        let withoutCredit = fold(title)
            .replacingOccurrences(of: #"[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: .regularExpression)
        return Set(words(withoutCredit)).subtracting(words(normalizeTitle(title)))
    }

    private static func words(_ s: String) -> [String] {
        String(s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
            .split(separator: " ").map(String.init)
    }

    static func isVersion(of a: String, _ b: String) -> Bool {
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard long.hasPrefix(short + " ") else { return false }
        let extra = long.dropFirst(short.count + 1).split(separator: " ")
        return !extra.isEmpty && extra.allSatisfy { versionWords.contains($0) || $0.allSatisfy(\.isNumber) }
    }

    // MARK: - Normalizing

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func normalizeTitle(_ title: String) -> String {
        var s = fold(title)
        s = s.replacingOccurrences(of: #"[\(\[【][^\)\]】]*[\)\]】]"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\s+[-–—|]\s+.*\b(remaster(ed)?|version|edit|live|mix|mono|stereo|official|video|audio|lyrics?)\b.*$"#,
            with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = String(s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
        return s.split(separator: " ").joined(separator: " ")
    }

    static func artistNames(_ artist: String) -> Set<String> {
        let s = fold(artist).replacingOccurrences(of: " - topic", with: "").replacingOccurrences(of: "vevo", with: "")
        let parts = s.components(separatedBy: CharacterSet(charactersIn: ",&/;"))
            .flatMap { $0.components(separatedBy: " feat. ") }
            .flatMap { $0.components(separatedBy: " ft. ") }
            .flatMap { $0.components(separatedBy: " and ") }
            .flatMap { $0.components(separatedBy: " x ") }
        return Set(parts.map { $0.filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty })
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Bool {
        if !a.isDisjoint(with: b) { return true }
        // "kneecap" vs "kneecapofficial": one name contained in the other.
        return a.contains { x in b.contains { y in x.count >= 4 && y.count >= 4 && (x.contains(y) || y.contains(x)) } }
    }
}
