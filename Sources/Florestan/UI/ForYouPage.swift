import SwiftUI

/// Recommendations: songs related to what's already been imported, from YouTube or, offline, from Apple Intelligence.
struct ForYouPage: View {
    enum Source: String, CaseIterable, Identifiable {
        case youtube, appleIntelligence
        var id: String { rawValue }
        var title: String { self == .youtube ? "From YouTube" : "From Apple Intelligence" }
        var subtitle: String {
            self == .youtube
                ? "Songs related to what you've downloaded, picked from YouTube's recommendations."
                : "Ideas from Apple Intelligence, made on this Mac. Works offline; adding a song looks it up on YouTube."
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(RecommendationsModel.self) private var recommendations
    @AppStorage("forYouSource") private var source: Source = .youtube

    private var tint: Color { model.settings.theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "For you", subtitle: source.subtitle) {
                    Button {
                        refresh()
                    } label: {
                        Label(source == .youtube ? "Refresh" : "New ideas", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading || model.librarySongs.isEmpty
                              || (source == .appleIntelligence && recommendations.ideasUnavailableReason != nil))
                }
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding([.horizontal, .top], 24)

            if model.librarySongs.isEmpty {
                Message("Download a few songs first. Suggestions based on them will show up here.")
            } else if source == .youtube {
                youtubeContent
            } else {
                ideasContent
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: source) { loadIfNeeded() }
    }

    private var isLoading: Bool {
        source == .youtube ? recommendations.phase == .loading : recommendations.ideaPhase == .loading
    }

    private func refresh() {
        if source == .youtube { recommendations.refresh(using: model) } else { recommendations.suggestIdeas(using: model) }
    }

    private func loadIfNeeded() {
        switch source {
        case .youtube: recommendations.refreshIfStale(using: model)
        case .appleIntelligence:
            if recommendations.ideas.isEmpty && recommendations.ideaPhase == .idle { recommendations.suggestIdeas(using: model) }
        }
    }

    @ViewBuilder private var youtubeContent: some View {
        if recommendations.phase == .loading && recommendations.items.isEmpty {
            Loading("Finding songs you might like…")
        } else if case .failed(let why) = recommendations.phase, recommendations.items.isEmpty {
            Message(why + " Offline? Try “From Apple Intelligence”.")
        } else {
            List(recommendations.items) { item in
                RecommendationRow(item: item, tint: tint)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var ideasContent: some View {
        if let reason = recommendations.ideasUnavailableReason {
            Message(reason)
        } else if recommendations.ideaPhase == .loading {
            Loading("Apple Intelligence is thinking about your music…")
        } else if case .failed(let why) = recommendations.ideaPhase, recommendations.ideas.isEmpty {
            Message(why)
        } else {
            List(recommendations.ideas) { idea in
                IdeaRow(idea: idea, tint: tint)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct Message: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).foregroundStyle(.secondary).padding(.horizontal, 24)
        Spacer()
    }
}

private struct Loading: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        Spacer()
    }
}

private struct RecommendationRow: View {
    @Environment(AppModel.self) private var model
    @Environment(RecommendationsModel.self) private var recommendations
    var item: Recommendation
    var tint: Color

    private var isAdded: Bool { recommendations.added.contains(item.videoID) || model.isInLibrary(item.videoID) }

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: item.thumbnailURL, size: 44, corner: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                Text(item.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Text("Because you added \(item.because)").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {
                NSWorkspace.shared.open(URL(string: item.url)!)
            } label: {
                Image(systemName: "play.rectangle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Listen on YouTube")
            .accessibilityLabel("Listen to \(item.title) on YouTube")
            if isAdded {
                Label("Added", systemImage: "checkmark").font(.callout).foregroundStyle(tint)
            } else {
                Button {
                    recommendations.dismiss(item)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Not interested")
                .accessibilityLabel("Not interested in \(item.title)")
                Button("Add") { recommendations.add(item, using: model) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .help("Download and add to Apple Music")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct IdeaRow: View {
    @Environment(AppModel.self) private var model
    @Environment(RecommendationsModel.self) private var recommendations
    var idea: IdeaRecommendation
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(tint.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "sparkles").foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(idea.title).lineLimit(1)
                Text(idea.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let error = recommendations.ideaErrors[idea.id] {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Link(destination: idea.searchURL) {
                Label("Search on YouTube", systemImage: "magnifyingglass")
                    .font(.callout)
            }
            .help("Open a YouTube search for this song")
            if recommendations.ideasAdded.contains(idea.id) {
                Label("Added", systemImage: "checkmark").font(.callout).foregroundStyle(tint)
            } else if recommendations.resolving.contains(idea.id) {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    recommendations.dismiss(idea)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Not interested")
                .accessibilityLabel("Not interested in \(idea.title)")
                Button("Add") { recommendations.add(idea, using: model) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .help("Find it on YouTube, then download and add it to Apple Music")
            }
        }
        .padding(.vertical, 4)
    }
}
