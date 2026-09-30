import SwiftUI

/// The colored frame around Florestan's content. Picked in Settings, like Arc's Spaces.
enum FrameTheme: String, CaseIterable, Identifiable {
    case dusk, lagoon, grove, graphite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dusk: "Dusk"
        case .lagoon: "Lagoon"
        case .grove: "Grove"
        case .graphite: "Graphite"
        }
    }

    /// Nine colors for a 3×3 mesh, row by row.
    var mesh: [Color] {
        switch self {
        case .dusk:
            [.hex(0x4B2FC9), .hex(0x7A3FD6), .hex(0xB34BD1),
             .hex(0x6A3AD8), .hex(0xC24FC4), .hex(0xFF6F91),
             .hex(0xA24BD6), .hex(0xFF7A9C), .hex(0xFFB08A)]
        case .lagoon:
            [.hex(0x0B4FB8), .hex(0x1471D6), .hex(0x1E9BD0),
             .hex(0x1467C9), .hex(0x1FA8C4), .hex(0x2EC7B5),
             .hex(0x1C8FC9), .hex(0x33CDB0), .hex(0x8BE6CF)]
        case .grove:
            [.hex(0x0F5C3A), .hex(0x1D7A4A), .hex(0x3E9A4F),
             .hex(0x1A6E45), .hex(0x4AA852), .hex(0x8CC653),
             .hex(0x3A9450), .hex(0x9BD05A), .hex(0xDCE08A)]
        case .graphite:
            [.hex(0x24262B), .hex(0x33363D), .hex(0x444852),
             .hex(0x2E3137), .hex(0x4A4E57), .hex(0x5E636D),
             .hex(0x3C4047), .hex(0x61666F), .hex(0x80858E)]
        }
    }

    /// The color used for accents inside the content card.
    var accent: Color { mesh[4] }
}

/// Eusebius, Florestan's calm other half, gets its own muted palette.
enum Eusebius {
    static let mesh: [Color] = [
        .hex(0xB9C6D9), .hex(0xC9D2E3), .hex(0xD6DCEA),
        .hex(0xC3CEDD), .hex(0xD8DEEA), .hex(0xE2E6EF),
        .hex(0xCBD6DE), .hex(0xDDE4E8), .hex(0xE9ECEF),
    ]
    static let ink = Color.hex(0x3B4658)
    static let accent = Color.hex(0x5E7394)
    static let paper = Color.hex(0xF7F8FB)
}

extension Color {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// The frame gradient. Drifts slowly while Florestan is working; still otherwise.
struct FrameBackground: View {
    var colors: [Color]
    var flowing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !flowing || reduceMotion)) { context in
            let t = flowing && !reduceMotion ? context.date.timeIntervalSinceReferenceDate : 0
            MeshGradient(width: 3, height: 3, points: points(at: t), colors: colors)
        }
        .animation(.easeInOut(duration: 0.8), value: colors)
    }

    private func points(at t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.5)) * 0.12
        let b = Float(cos(t * 0.37)) * 0.12
        return [
            [0, 0], [0.5 + a * 0.6, 0], [1, 0],
            [0, 0.5 + b * 0.6], [0.5 + a, 0.5 + b], [1, 0.5 - a * 0.6],
            [0, 1], [0.5 - b * 0.6, 1], [1, 1],
        ]
    }
}

/// "Florestan" in bold rounded type, with a small monospaced ".exe" joke.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("Florestan")
                .font(.system(size: size, weight: .heavy, design: .rounded))
            Text(".exe")
                .font(.system(size: size * 0.62, weight: .medium, design: .monospaced))
                .opacity(0.65)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Florestan.exe")
    }
}
