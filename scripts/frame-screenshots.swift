// Turns the raw captures of `Florestan --snapshot` into the README's product shots: each window with rounded
// corners, its window buttons and a soft shadow on a light backdrop, and a hero image of a Mac desktop with the menu
// bar panel open over the main window.
// Usage: swift scripts/frame-screenshots.swift <raw-dir> <output-dir>
import AppKit
import SwiftUI

let raw = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])

func color(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// A capture at its pixel size (captures are 2× the window's size in points).
struct Capture {
    let image: NSImage
    let size: CGSize
    init(_ name: String) {
        guard let image = NSImage(contentsOf: raw.appendingPathComponent(name)),
              let rep = image.representations.first else { fatalError("missing capture \(name)") }
        self.image = image
        size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}

/// The red, yellow and green buttons. The capture draws them as dark dots, so they're painted over.
struct WindowButtons: View {
    var body: some View {
        HStack(spacing: 21) {
            ForEach([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32], id: \.self) { hex in
                Circle().fill(color(hex))
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1.5))
                    .frame(width: 25, height: 25)
            }
        }
        .padding(.leading, 19.5)
        .padding(.top, 19.5)
    }
}

/// A window or panel as macOS draws it: rounded, outlined, with a two-layer shadow.
struct Framed: View {
    let capture: Capture
    var isWindow = true
    var radius: CGFloat = 26

    var body: some View {
        Image(nsImage: capture.image)
            .resizable()
            .frame(width: capture.size.width, height: capture.size.height)
            .overlay(alignment: .topLeading) { if isWindow { WindowButtons() } }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.black.opacity(0.14), lineWidth: 2))
            .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
            .shadow(color: .black.opacity(0.24), radius: 56, y: 32)
    }
}

/// The light backdrop of the feature shots, tinted with the app's Dusk colours.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [color(0xF6F3FB), color(0xE9E3F4)], startPoint: .top, endPoint: .bottom)
            Circle().fill(color(0xB34BD1).opacity(0.16)).frame(width: 1400).blur(radius: 220).offset(x: -700, y: -500)
            Circle().fill(color(0xFF7A9C).opacity(0.14)).frame(width: 1200).blur(radius: 220).offset(x: 800, y: 600)
        }
    }
}

/// A desktop in a lighter, softer take on the Dusk colours, so the window's own Dusk frame stands out against it.
struct Wallpaper: View {
    var body: some View {
        let dusk: [UInt32] = [0x5B4BC9, 0x7A63E0, 0x9C78E6, 0xA592EC, 0xCDB0F2, 0xF2B8CF, 0xC9A5EE, 0xF6C6D4, 0xFFD9C2]
        MeshGradient(width: 3, height: 3,
                     points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.45, 0.55], [1, 0.45], [0, 1], [0.5, 1], [1, 1]],
                     colors: dusk.map(color))
    }
}

/// The right end of a macOS menu bar, with Florestan's note highlighted as if just clicked.
struct MenuBar: View {
    let noteX: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black.opacity(0.10)).frame(height: 56)
            Capsule().fill(.white.opacity(0.28)).frame(width: 72, height: 44).offset(x: noteX - 36, y: 6)
            Image(systemName: "music.note").font(.system(size: 28, weight: .medium)).foregroundStyle(.white)
                .frame(width: 72, height: 56).offset(x: noteX - 36)
            HStack(spacing: 44) {
                ForEach(["wifi", "battery.75percent", "magnifyingglass", "switch.2"], id: \.self) { name in
                    Image(systemName: name).font(.system(size: 27, weight: .medium))
                }
                Text("Thu 5 Nov  9:41").font(.system(size: 27, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(height: 56)
            .offset(x: noteX + 80)
        }
    }
}

struct FeatureShot: View {
    let capture: Capture
    var isWindow = true
    let padding: CGFloat = 140

    var body: some View {
        ZStack {
            Backdrop()
            Framed(capture: capture, isWindow: isWindow)
        }
        .frame(width: capture.size.width + padding * 2, height: capture.size.height + padding * 2)
    }
}

struct Hero: View {
    let window: Capture
    let panel: Capture
    static let size = CGSize(width: 2880, height: 1800)

    var body: some View {
        let noteX: CGFloat = 2140
        ZStack(alignment: .topLeading) {
            Wallpaper()
            Framed(capture: window).offset(x: 260, y: 300)
            Framed(capture: panel, isWindow: false, radius: 30).offset(x: noteX - panel.size.width / 2, y: 76)
            MenuBar(noteX: noteX)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
    }
}

@MainActor func save(_ view: some View, as name: String, jpeg: Bool = false) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed: \(name)") }
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                    : rep.representation(using: .png, properties: [:])
    try data!.write(to: out.appendingPathComponent(name))
    print(name, rep.pixelsWide, "×", rep.pixelsHigh)
}

@MainActor func render() throws {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    // JPEG: the soft backdrops make PNGs several megabytes each.
    for page in ["downloads", "forYou", "library", "eusebius", "settings"] {
        try save(FeatureShot(capture: Capture("\(page).png")), as: "\(page).jpg", jpeg: true)
    }
    let panel = Capture("menu-panel.png")
    try save(FeatureShot(capture: panel, isWindow: false), as: "menu-panel.jpg", jpeg: true)
    try save(Hero(window: Capture("downloads.png"), panel: panel), as: "hero.jpg", jpeg: true)
}
try MainActor.assumeIsolated { try render() }
