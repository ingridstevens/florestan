// Renders Support/AppIcon.icns: the Dusk frame gradient with a white note.
// Usage: swift scripts/make-icon.swift <output-dir>
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        let dusk: [Color] = [0x4B2FC9, 0x7A3FD6, 0xB34BD1, 0x6A3AD8, 0xC24FC4, 0xFF6F91, 0xA24BD6, 0xFF7A9C, 0xFFB08A].map {
            Color(red: Double(($0 >> 16) & 0xFF) / 255, green: Double(($0 >> 8) & 0xFF) / 255, blue: Double($0 & 0xFF) / 255)
        }
        ZStack {
            MeshGradient(width: 3, height: 3,
                         points: [[0, 0], [0.5, 0], [1, 0], [0, 0.45], [0.55, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                         colors: dusk)
            Image(systemName: "music.note")
                .font(.system(size: 440, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                .offset(x: -14, y: 6)
        }
        .frame(width: 824, height: 824)
        .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render() throws {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    let iconset = out.appendingPathComponent("AppIcon.iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = size * scale
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: cg, size: .init(width: 1024, height: 1024)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
        }
    }
}
try MainActor.assumeIsolated { try render() }
