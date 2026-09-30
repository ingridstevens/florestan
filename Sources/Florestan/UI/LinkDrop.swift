import AppKit
import FlorestanCore
import SwiftUI
import UniformTypeIdentifiers

/// Accepts a YouTube link dragged in from a browser (address bar, a link on a page, or selected text) and downloads it.
struct LinkDropTarget: ViewModifier {
    @Environment(AppModel.self) private var model
    @ViewState private var targeted = false
    @ViewState private var feedback: String?
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.url, .plainText], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                if provider.canLoadObject(ofClass: NSURL.self) {
                    _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                        let text = (object as? NSURL)?.absoluteString ?? ""
                        Task { @MainActor in handle(text) }
                    }
                    return true
                }
                if provider.canLoadObject(ofClass: NSString.self) {
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        let text = (object as? String) ?? ""
                        Task { @MainActor in handle(text) }
                    }
                    return true
                }
                return false
            }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: cornerRadius).fill(.black.opacity(0.25)))
                        .overlay(
                            Label("Drop to download", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        )
                        .padding(6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if let feedback {
                    Text(feedback)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: targeted)
            .animation(.snappy, value: feedback)
    }

    private func handle(_ text: String) {
        let message: String = switch model.submit(text) {
        case .queued: Link.parse(text)?.isPlaylist == true ? "Downloading playlist" : "Downloading song"
        case .notALink: "That isn't a YouTube link"
        case .alreadyQueued: "That link is already downloading"
        case .toolsMissing: "Install yt-dlp and ffmpeg first"
        }
        feedback = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if feedback == message { feedback = nil }
        }
    }
}

extension View {
    func acceptsLinkDrops(cornerRadius: CGFloat = 12) -> some View {
        modifier(LinkDropTarget(cornerRadius: cornerRadius))
    }
}
