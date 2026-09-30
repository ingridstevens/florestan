import SwiftUI

struct SettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(title: "Settings")

                SettingGroup("Frame color") {
                    HStack(spacing: 14) {
                        ForEach(FrameTheme.allCases) { theme in
                            ThemeSwatch(theme: theme, selected: settings.theme == theme) {
                                withAnimation(.easeInOut(duration: 0.5)) { settings.theme = theme }
                            }
                        }
                    }
                }

                SettingGroup("General") {
                    Toggle("Open Florestan when you log in", isOn: Binding(
                        get: { _ = settings.launchAtLoginRevision; return settings.launchAtLogin },
                        set: { settings.launchAtLogin = $0 }
                    ))
                    LabeledContent("Download shortcut") {
                        Text("⌥⌘Y").font(.system(.body, design: .rounded).weight(.semibold))
                    }
                }

                SettingGroup("YouTube") {
                    Toggle("Update yt-dlp automatically", isOn: $settings.keepYTDLPUpdated)
                    Text("Checks once a day. YouTube changes often, and older versions of yt-dlp stop working.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Toggle("Use my YouTube login from", isOn: $settings.useBrowserLogin)
                        Picker("", selection: $settings.cookieBrowser) {
                            ForEach(CookieBrowser.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        .disabled(!settings.useBrowserLogin)
                    }
                    Text("Helps when YouTube blocks your network, and for age-restricted videos. You need to be signed in to YouTube in that browser. Safari needs Full Disk Access for Florestan.exe.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingGroup("Tools") {
                    LabeledContent("yt-dlp", value: model.ytdlpVersion ?? "Not installed")
                    LabeledContent("ffmpeg", value: Downloader.ffmpeg == nil ? "Not installed" : "Installed")
                    HStack {
                        Button("Check again") { Task { await model.refreshTools() } }
                        Button("Show downloads folder") {
                            let folder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("Florestan")
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content
        }
    }
}

private struct ThemeSwatch: View {
    var theme: FrameTheme
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                MeshGradient(width: 3, height: 3,
                             points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.5, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                             colors: theme.mesh)
                    .frame(width: 64, height: 44)
                    .clipShape(.rect(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.primary : .clear, lineWidth: 2).padding(-4))
                Text(theme.name).font(.caption).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
