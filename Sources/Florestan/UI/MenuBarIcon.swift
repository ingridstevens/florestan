import AppKit

/// The menu bar icon: a music note, and while Florestan downloads, a little arrow that keeps dropping in beside it
/// while the note bobs.
/// Menu bar labels don't play SwiftUI animations, so the frames are drawn once and the app delegate steps through them.
enum MenuBarIcon {
    static let idle = draw(arrowAt: nil)

    /// The arrow falls from above the note's head to its foot, fading in and out, and the note bobs as it lands.
    static let downloading: [NSImage] = [
        draw(arrowAt: (y: 13, alpha: 0.35)),
        draw(arrowAt: (y: 10, alpha: 0.8)),
        draw(arrowAt: (y: 7, alpha: 1)),
        draw(arrowAt: (y: 4, alpha: 1), noteLift: 1),
        draw(arrowAt: (y: 1, alpha: 0.5), noteLift: 1.5),
        draw(arrowAt: nil, noteLift: 0.5),
    ]

    static let frameInterval: Duration = .milliseconds(180)

    private static let size = NSSize(width: 24, height: 18)

    private static func draw(arrowAt arrow: (y: CGFloat, alpha: CGFloat)?, noteLift: CGFloat = 0) -> NSImage {
        let note = symbol("music.note", pointSize: 14, weight: .medium)
        let arrowImage = symbol("arrow.down", pointSize: 8, weight: .heavy)
        let image = NSImage(size: size, flipped: false) { _ in
            note?.draw(in: NSRect(x: 2, y: (size.height - (note?.size.height ?? 0)) / 2 + noteLift,
                                  width: note?.size.width ?? 0, height: note?.size.height ?? 0))
            if let arrow, let arrowImage {
                arrowImage.draw(in: NSRect(x: size.width - arrowImage.size.width - 1, y: arrow.y,
                                           width: arrowImage.size.width, height: arrowImage.size.height),
                                from: .zero, operation: .sourceOver, fraction: arrow.alpha)
            }
            return true
        }
        // A template image follows the menu bar's light or dark appearance.
        image.isTemplate = true
        image.accessibilityDescription = arrow == nil ? "Florestan.exe" : "Florestan.exe, downloading"
        return image
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    }
}

/// Steps through the downloading frames while the Queue is busy, and rests on the plain note otherwise.
@MainActor @Observable
final class MenuBarAnimator {
    private(set) var image = MenuBarIcon.idle

    init(model: AppModel) {
        Task { [weak self] in
            var frame = 0
            while let self {
                if model.isBusy {
                    image = MenuBarIcon.downloading[frame % MenuBarIcon.downloading.count]
                    frame += 1
                    try? await Task.sleep(for: MenuBarIcon.frameInterval)
                } else {
                    if image !== MenuBarIcon.idle { image = MenuBarIcon.idle }
                    frame = 0
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }
}
