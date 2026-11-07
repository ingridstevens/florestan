import AppKit

/// The menu bar icon: a music note. While Florestan downloads, tiny notes drift into its flag and it fills
/// from the bottom like a glass, as far as the download has got; full means the song or playlist is in Apple Music.
/// Menu bar labels don't play SwiftUI animations, so each frame is drawn as a template image and the animator
/// swaps them a few times a second.
enum MenuBarIcon {
    static let idle = image(described: "Florestan.exe") { note, _ in
        note.draw(in: noteRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// One frame of the filling note. `time` drives the pouring notes and the ripple; `progress` (0…1) sets the level.
    /// With `moving` off (Reduce Motion), it's only the level: a still waterline and no falling notes.
    static func filling(time t: Double, progress: Double, moving: Bool = true) -> NSImage {
        image(described: "Florestan.exe, downloading") { note, tinyNote in
            // The empty part of the glass.
            note.draw(in: noteRect, from: .zero, operation: .sourceOver, fraction: 0.3, respectFlipped: true, hints: nil)

            // The full part: the note again, clipped below a rippling waterline.
            let level = noteRect.maxY - CGFloat(max(progress, 0.06)) * noteRect.height
            let ripple: CGFloat = moving ? 0.45 : 0
            let water = NSBezierPath()
            water.move(to: NSPoint(x: 0, y: size.height))
            for step in 0...48 {
                let x = CGFloat(step) / 2
                water.line(to: NSPoint(x: x, y: level + sin(x * 0.9 + CGFloat(t) * 6) * ripple))
            }
            water.line(to: NSPoint(x: size.width, y: size.height))
            water.close()
            NSGraphicsContext.saveGraphicsState()
            water.addClip()
            note.draw(in: noteRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()

            // Tiny notes falling in the free space beside the note, drifting into its flag and fading as they arrive,
            // so they never clutter the note itself.
            guard moving, let tinyNote else { return }
            let flag = NSPoint(x: noteRect.maxX - 1.5, y: noteRect.minY + 3)
            let every = 0.3, fall = 0.9
            var i = Int(floor((t - fall) / every))
            while Double(i) * every <= t {
                defer { i += 1 }
                let age = t - Double(i) * every
                guard age >= 0, age < fall else { continue }
                let k = CGFloat(age / fall)
                let startX = noteRect.maxX + 3 + CGFloat(seededRandom(i)) * (size.width - noteRect.maxX - 4)
                let x = startX + (flag.x - startX) * k * k
                let y = -2 + (flag.y + 2) * k
                let alpha = min(age * 6, 1) * Double(min(1.6 * (1 - k), 1))
                guard alpha > 0 else { continue }
                tinyNote.draw(in: NSRect(x: x - tinyNote.size.width / 2, y: y - tinyNote.size.height, width: tinyNote.size.width,
                                         height: tinyNote.size.height),
                              from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            }
        }
    }

    /// How often the animator draws a new frame while downloading.
    static let frameInterval: Duration = .milliseconds(125)

    private static let size = NSSize(width: 24, height: 18)
    private static let note = symbol("music.note", pointSize: 14, weight: .medium)
    private static let tinyNote = symbol("music.note", pointSize: 4, weight: .bold)
    /// Where the note sits, in the flipped (top-down) coordinates the frames are drawn in.
    private static let noteRect: NSRect = {
        let s = note?.size ?? NSSize(width: 12, height: 15)
        return NSRect(x: 2, y: (size.height - s.height) / 2, width: s.width, height: s.height)
    }()

    private static func image(described description: String, draw: @escaping (NSImage, NSImage?) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            if let note { draw(note, tinyNote) }
            return true
        }
        // A template image follows the menu bar's light or dark appearance.
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }

    /// The same "random" number for the same falling note every time, so the pour looks steady.
    private static func seededRandom(_ i: Int) -> Double {
        let x = sin(Double(i) * 127.1 + 311.7) * 43758.5453
        return x - floor(x)
    }
}

/// Draws the filling note while the Queue is busy, and rests on the plain note otherwise. With Reduce Motion on, the
/// note only shows the level, redrawn once a second.
@MainActor @Observable
final class MenuBarAnimator {
    private(set) var image = MenuBarIcon.idle

    init(model: AppModel) {
        Task { [weak self] in
            let start = Date.now
            var shown = 0.0
            while let self {
                if model.isBusy {
                    // Eases toward the real progress, so the level rises smoothly instead of jumping song by song.
                    let target = model.activeJob?.progress ?? 0
                    let moving = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    shown = !moving || target < shown - 0.2 ? target : shown + (target - shown) * 0.25
                    image = MenuBarIcon.filling(time: Date.now.timeIntervalSince(start), progress: shown, moving: moving)
                    try? await Task.sleep(for: moving ? MenuBarIcon.frameInterval : .seconds(1))
                } else {
                    if image !== MenuBarIcon.idle { image = MenuBarIcon.idle }
                    shown = 0
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }
}
