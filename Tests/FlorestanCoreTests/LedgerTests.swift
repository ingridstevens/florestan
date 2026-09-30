import Foundation
import Testing
@testable import FlorestanCore

@Suite struct LedgerTests {
    @Test func persistsAcrossLoads() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("ledger.json")
        let store = LedgerStore(fileURL: url)
        let entry = LedgerEntry(videoID: "v1", metadata: .init(title: "T", artist: "A", album: "T"), musicTrackID: "ABC")
        try await store.record(entry)
        try await store.setMirroredPlaylist("PLAYLIST", for: "PL1")

        let reloaded = LedgerStore(fileURL: url)
        #expect(await reloaded.contains("v1"))
        #expect(await reloaded.mirroredPlaylist(for: "PL1") == "PLAYLIST")

        try await reloaded.forget("v1")
        #expect(await LedgerStore(fileURL: url).contains("v1") == false)
    }
}
