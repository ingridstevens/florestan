import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case downloads, forYou, library, eusebius, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .forYou: "For you"
        case .library: "Imported songs"
        case .eusebius: "Eusebius"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .downloads: "arrow.down.circle"
        case .forYou: "sparkles"
        case .library: "music.note.list"
        case .eusebius: "moon.stars"
        case .settings: "gearshape"
        }
    }
}

/// Arc-style window: the theme gradient frames a floating content card.
struct MainWindow: View {
    @Environment(AppModel.self) private var model

    private var isEusebius: Bool { model.selectedSection == .eusebius }

    var body: some View {
        ZStack {
            FrameBackground(colors: isEusebius ? Eusebius.mesh : model.settings.theme.mesh,
                            flowing: model.isBusy && !isEusebius)
                .ignoresSafeArea()
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 196)
                VStack(spacing: 0) {
                    if !isEusebius {
                        // Like Arc's command bar, the link field lives on the frame, not in the page.
                        LinkField(prefillFromClipboard: false, large: true)
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                            .padding(.trailing, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                        .clipShape(.rect(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                        .padding([.bottom, .trailing], 8)
                        .padding(.top, isEusebius ? 8 : 0)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    @ViewBuilder private var content: some View {
        switch model.selectedSection {
        case .downloads: DownloadsPage()
        case .forYou: ForYouPage()
        case .library: LibraryPage()
        case .eusebius: EusebiusPage()
        case .settings: SettingsPage()
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let isEusebius = model.selectedSection == .eusebius
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if isEusebius {
                    Text("Eusebius")
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Eusebius.ink)
                } else {
                    Wordmark(size: 20)
                }
            }
            .padding(.leading, 10)
            .padding(.top, 38)
            .padding(.bottom, 18)
            .animation(.easeInOut(duration: 0.3), value: isEusebius)

            ForEach(Section.allCases) { section in
                SidebarItem(section: section, selected: model.selectedSection == section, onEusebius: isEusebius) {
                    withAnimation(.snappy(duration: 0.25)) { model.selectedSection = section }
                }
            }
            Spacer()
            if let version = model.ytdlpVersion {
                Text("yt-dlp \(version)")
                    .font(.caption2)
                    .foregroundStyle(isEusebius ? Eusebius.ink.opacity(0.6) : .white.opacity(0.6))
                    .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }
}

private struct SidebarItem: View {
    var section: Section
    var selected: Bool
    var onEusebius: Bool
    var action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .frame(width: 18)
                Text(section.title)
                Spacer()
            }
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .foregroundStyle(onEusebius ? AnyShapeStyle(Eusebius.ink) : AnyShapeStyle(.white))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(selected ? (onEusebius ? 0.55 : 0.22) : hovering ? 0.1 : 0))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Page title used at the top of each content card.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
