// Draws made-up cover art for the demo songs of docs/demo, one PNG per video ID, so the screenshots show no real
// video's thumbnail. Each cover's colours and shape come from its place in the list, so reruns draw the same pictures.
// Usage: swift scripts/make-demo-thumbnails.swift <docs/demo> <output-dir>
import AppKit
import SwiftUI

struct Cover: View {
    var seed: Int

    private static let palettes: [[UInt32]] = [
        [0x4B2FC9, 0xB34BD1, 0xFF7A9C], [0x1E6FD9, 0x3FB8C9, 0x9BE8C9], [0x2E7D4F, 0x7CC36B, 0xE6E08A],
        [0xE2574C, 0xF29F4B, 0xF7D774], [0x2B2D42, 0x5C6B8A, 0xB8C4E0], [0x8A2BE2, 0xE0479E, 0xFFC1A1],
        [0x0F4C5C, 0x2A9D8F, 0xE9C46A], [0x6D1A36, 0xC0395A, 0xF2A07B],
    ]
    private static let symbols = ["waveform", "music.note", "circle.hexagongrid", "sparkles", "moon.stars",
                                  "sun.max", "leaf", "cloud", "metronome", "headphones", "guitars", "pianokeys"]

    var body: some View {
        let colors = Self.palettes[seed % Self.palettes.count].map {
            Color(red: Double(($0 >> 16) & 0xFF) / 255, green: Double(($0 >> 8) & 0xFF) / 255, blue: Double($0 & 0xFF) / 255)
        }
        ZStack {
            LinearGradient(colors: colors, startPoint: seed % 2 == 0 ? .topLeading : .topTrailing,
                           endPoint: seed % 2 == 0 ? .bottomTrailing : .bottomLeading)
            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: 220, height: 220)
                .offset(x: CGFloat(seed % 5) * 30 - 60, y: CGFloat(seed % 3) * 50 - 50)
            Image(systemName: Self.symbols[(seed * 5) % Self.symbols.count])
                .font(.system(size: 120, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: 320, height: 320)
    }
}

/// Every video ID in the demo history and suggestions.
func videoIDs(in demo: URL) throws -> [String] {
    struct Track: Decodable { var videoID: String }
    struct Job: Decodable { var tracks: [Track] }
    struct Recommendations: Decodable { struct Item: Decodable { var videoID: String }; var items: [Item] }
    let jobs = try JSONDecoder().decode([Job].self, from: Data(contentsOf: demo.appendingPathComponent("history.json")))
    let recommendations = try JSONDecoder().decode(Recommendations.self, from: Data(contentsOf: demo.appendingPathComponent("recommendations.json")))
    return jobs.flatMap { $0.tracks.map(\.videoID) } + recommendations.items.map(\.videoID)
}

@MainActor func render() throws {
    let demo = URL(fileURLWithPath: CommandLine.arguments[1])
    let out = URL(fileURLWithPath: CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (index, id) in try videoIDs(in: demo).enumerated() {
        let renderer = ImageRenderer(content: Cover(seed: index))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { fatalError("render failed") }
        try png.write(to: out.appendingPathComponent("\(id).png"))
    }
}
try MainActor.assumeIsolated { try render() }
