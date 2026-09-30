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
                    Toggle("Put new songs from YouTube videos onto their albums", isOn: $settings.tidyNewSongs)
                    Text("Looks up the album on YouTube Music after each download. Imported songs › Tidy albums does the same for older songs.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    LeftoversRow()
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

                SettingGroup("About") { AboutSection() }
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

/// Where the names come from.
private struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Robert Schumann gave the two sides of his personality names. **Florestan** was the fiery, impulsive one; **Eusebius** the dreamy, thoughtful one. They signed his music criticism, argued with each other in his essays as members of the Davidsbündler, an imaginary society he invented to defend new music, and each got a piece of their own in his *Carnaval*. He even signed the dances of his *Davidsbündlertänze* one by one with F. or E.")
                .fixedSize(horizontal: false, vertical: true)
            Text("This app is split the same way. Florestan rushes in and grabs the music; Eusebius listens to all of it and sorts it by feel.")
                .fixedSize(horizontal: false, vertical: true)
            Text("And the .exe? A Windows program ending on a Mac app. It's a joke.")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Davidsbündler", destination: URL(string: "https://en.wikipedia.org/wiki/Davidsb%C3%BCndler")!)
                Link("Robert Schumann", destination: URL(string: "https://en.wikipedia.org/wiki/Robert_Schumann")!)
                Link("Carnaval", destination: URL(string: "https://en.wikipedia.org/wiki/Carnaval_(Schumann)")!)
            }
            .font(.callout)
            Text("Florestan.exe \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

/// Leftover files from downloads that failed or were stopped.
private struct LeftoversRow: View {
    @Environment(AppModel.self) private var model
    @ViewState private var summary: AppModel.Leftovers?

    var body: some View {
        HStack {
            if let summary, summary.count > 0 {
                Text("\(summary.count) leftover \(summary.count == 1 ? "file" : "files") from failed downloads, \(ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file))")
                Spacer()
                Button("Clean up") {
                    model.cleanUpLeftovers()
                    self.summary = model.leftoverSummary()
                }
            } else {
                Text("No leftover files. Florestan also clears them out after three days.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { summary = model.leftoverSummary() }
    }
}
