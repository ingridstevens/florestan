import Foundation
import FlorestanCore

/// One song within a Job. See CONTEXT.md.
struct Track: Identifiable, Codable, Hashable {
    enum State: Codable, Hashable {
        case waiting
        case downloading(Double)
        case importing
        case imported
        /// Already in the Ledger.
        case skipped
        case failed(String)
    }

    var id: String { videoID }
    var videoID: String
    var title: String
    var artist: String?
    var state: State = .waiting

    var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")! }

    var isDone: Bool {
        switch state {
        case .imported, .skipped, .failed: true
        default: false
        }
    }
}

/// The work of processing one Link. See CONTEXT.md.
struct Job: Identifiable, Codable {
    enum Phase: Codable, Hashable {
        case queued
        case preparing(String)
        case running
        case finished
        case failed(String)
    }

    var id = UUID()
    var link: Link
    var title: String
    var phase: Phase = .queued
    var tracks: [Track] = []
    var createdAt = Date.now
    var finishedAt: Date?

    var isActive: Bool {
        switch phase {
        case .preparing, .running: true
        default: false
        }
    }

    var isFinished: Bool {
        switch phase {
        case .finished, .failed: true
        default: false
        }
    }

    var importedCount: Int { tracks.count { $0.state == .imported } }
    var skippedCount: Int { tracks.count { $0.state == .skipped } }
    var failedCount: Int { tracks.count { if case .failed = $0.state { true } else { false } } }
    var doneCount: Int { tracks.count(where: \.isDone) }

    /// Overall progress 0…1, counting partial downloads.
    var progress: Double {
        guard !tracks.isEmpty else { return 0 }
        let sum = tracks.reduce(0.0) { total, track in
            switch track.state {
            case .waiting: total
            case .downloading(let p): total + p * 0.9
            case .importing: total + 0.95
            default: total + 1
            }
        }
        return sum / Double(tracks.count)
    }

    /// A short status line, e.g. "12 of 23 · 1 failed".
    var summary: String {
        switch phase {
        case .queued: return "Waiting"
        case .preparing(let what): return what
        case .failed(let why): return why
        case .running, .finished:
            var parts: [String] = []
            if link.isPlaylist || tracks.count > 1 {
                parts.append(phase == .running ? "\(doneCount) of \(tracks.count)" : "\(importedCount) added")
            } else if phase == .finished {
                parts.append(importedCount == 1 ? "Added to Apple Music" : skippedCount == 1 ? "Already in your library" : "Not added")
            } else {
                parts.append("Downloading")
            }
            if link.isPlaylist && skippedCount > 0 { parts.append("\(skippedCount) already had") }
            if failedCount > 0 { parts.append("\(failedCount) failed") }
            return parts.joined(separator: ", ")
        }
    }
}
