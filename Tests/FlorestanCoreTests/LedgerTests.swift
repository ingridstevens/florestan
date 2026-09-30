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

    @Test func readsLedgersWrittenBeforeRemovalsExisted() throws {
        let json = #"{"songs":{},"mirroredPlaylists":{"PL1":"ABC"}}"#
        let ledger = try JSONDecoder.florestan.decode(Ledger.self, from: Data(json.utf8))
        #expect(ledger.mirroredPlaylists["PL1"] == "ABC")
        #expect(ledger.removedFromPlaylists.isEmpty)
    }

    @Test func remembersRemovedSongs() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("ledger.json")
        let store = LedgerStore(fileURL: url)
        try await store.setRemoved(true, videoID: "v1", from: "PL1")
        #expect(await LedgerStore(fileURL: url).removedVideos(from: "PL1") == ["v1"])
        try await store.setRemoved(false, videoID: "v1", from: "PL1")
        #expect(await LedgerStore(fileURL: url).removedVideos(from: "PL1").isEmpty)
    }
}
