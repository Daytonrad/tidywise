import SwiftUI

/// The library: files on the left (filtered by topic), everything about the selected file on the right.
struct FilesView: View {
    @Environment(AppState.self) private var state
    @ViewState private var search = ""

    private struct Group: Identifiable {
        let slug: String
        let name: String
        let files: [FileItem]
        var id: String { slug }
    }

    /// All sorted files that match the search – grouped by topic, inbox first.
    private var allGroups: [Group] {
        let matching = state.moved.filter { f in
            search.isEmpty || [f.name, f.summary, f.keywords].contains { $0.localizedCaseInsensitiveContains(search) }
        }
        .sorted { ($0.movedAt ?? .distantPast) > ($1.movedAt ?? .distantPast) }
        var result: [Group] = []
        let inbox = matching.filter(\.isInInbox)
        if !inbox.isEmpty { result.append(Group(slug: "_inbox", name: "Inbox", files: inbox)) }
        var known = Set<String>()
        for t in state.config.topics {
            known.insert(t.slug)
            let files = matching.filter { $0.topic == t.slug && !$0.isInInbox }
            if !files.isEmpty { result.append(Group(slug: t.slug, name: t.name, files: files)) }
        }
        // Keep files whose topic was removed from Settings visible and editable.
        let orphanSlugs = Set(matching.filter { !$0.isInInbox }.compactMap(\.topic)).subtracting(known).sorted()
        for slug in orphanSlugs {
            let files = matching.filter { $0.topic == slug && !$0.isInInbox }
            if !files.isEmpty { result.append(Group(slug: slug, name: slug, files: files)) }
        }
        return result
    }

    var body: some View {
        let all = allGroups
        let groups = state.fileTopic == nil ? all : all.filter { $0.slug == state.fileTopic }
        let total = all.reduce(0) { $0 + $1.files.count }

        VStack(alignment: .leading, spacing: 14) {
            PageHeader("Files", subtitle: "Everything Tidywise has sorted. Select a file to see what it's about.")
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, DS.pagePadding)

            FilterChips(chips: [FilterChip(id: nil, title: "All", count: total)] + all.map {
                FilterChip(id: $0.slug, title: $0.name, count: $0.files.count,
                           symbol: TopicStyle.of($0.slug).symbol, color: TopicStyle.of($0.slug).color)
            }, selection: Binding(get: { state.fileTopic }, set: { state.fileTopic = $0 }))

            HStack(alignment: .top, spacing: DS.gap) {
                list(groups)
                detail.frame(minWidth: 320, idealWidth: 400, maxWidth: 400)
            }
            .padding(.horizontal, DS.pagePadding)
            .padding(.bottom, DS.pagePadding)
        }
        .pageFill()
        .background(DS.page)
        .searchable(text: $search, prompt: "Name, content or keyword")
    }

    private func list(_ groups: [Group]) -> some View {
        List(selection: Binding(get: { state.selectedFileID }, set: { state.selectedFileID = $0 })) {
            ForEach(groups) { g in
                Section {
                    ForEach(g.files) { f in
                        FileRow(file: f).tag(f.id)
                            .contextMenu {
                                Button("Open") { state.open(f) }
                                Button("Show in Finder") { state.reveal(f) }
                            }
                    }
                } header: {
                    if state.fileTopic == nil {
                        let style = TopicStyle.of(g.slug)
                        HStack(spacing: 7) {
                            Image(systemName: style.symbol).foregroundStyle(style.color)
                            Text(g.name).foregroundStyle(.primary)
                            Text("\(g.files.count)").foregroundStyle(.tertiary)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if groups.isEmpty {
                if search.isEmpty {
                    EmptyState(symbol: "folder", color: .gray, title: "No files yet",
                               text: "As soon as Tidywise has sorted something, you'll find it here.")
                } else {
                    EmptyState(symbol: "magnifyingglass", color: .gray, title: "No results",
                               text: "Nothing found for “\(search)”.")
                }
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.radius - 4, style: .continuous))
        .card(padding: 4)
    }

    @ViewBuilder private var detail: some View {
        if let f = state.files.first(where: { $0.id == state.selectedFileID && $0.status == "moved" }) {
            ScrollView {
                FileDetail(file: f).padding(DS.cardPadding + 2)
            }
            .frame(maxHeight: .infinity)
            .card(padding: 0)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 30)).foregroundStyle(.tertiary)
                Text("Select a file on the left").font(.body.weight(.semibold))
                Text("Then you'll see its summary, origin and topic here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
    }
}

struct FileRow: View {
    let file: FileItem

    var body: some View {
        HStack(spacing: 11) {
            FileIconView(ext: file.ext, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Text(file.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Format.shortRelative(file.movedAt)).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct FileDetail: View {
    @Environment(AppState.self) private var state
    let file: FileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            actions
            if let idea = file.newTopic, !idea.isEmpty, file.isInInbox {
                Notice(text: "The AI suggests a new topic: “\(idea)”. You can create new topics under Settings.",
                       systemImage: "lightbulb.fill", tint: .yellow)
            }

            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "What it's about", systemImage: "text.alignleft")
                Text(file.summary.isEmpty ? "No summary available." : file.summary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                let tags = file.keywords.components(separatedBy: ", ").filter { !$0.isEmpty }
                if !tags.isEmpty {
                    FlowLayout { ForEach(tags, id: \.self) { TagChip(text: $0) } }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "Origin", systemImage: "arrow.down.circle")
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    if let src = file.sourceURL, let url = URL(string: src) {
                        GridRow {
                            Text("Downloaded from").foregroundStyle(.secondary)
                            Link(url.host() ?? src, destination: url).lineLimit(1)
                        }
                    }
                    InfoRow("Previously in", Paths.folderName(of: file.origPath))
                    InfoRow("Now in", Paths.short(URL(fileURLWithPath: file.curPath ?? file.origPath).deletingLastPathComponent().path))
                    InfoRow("Sorted", file.movedAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Format.locale)) ?? "–")
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            FileIconView(ext: file.ext, size: 56)
            VStack(alignment: .leading, spacing: 7) {
                Text(file.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TopicPill(slug: file.isInInbox ? "_inbox" : file.topic,
                              name: file.isInInbox ? "Inbox" : state.config.topicName(file.topic))
                    ConfidenceLabel(value: file.confidence, threshold: state.config.minConfidence)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { state.open(file) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                .buttonStyle(.borderedProminent)
            Button { state.reveal(file) } label: { Label("In Finder", systemImage: "folder") }
            Menu {
                Section("Change topic") {
                    ForEach(state.config.topics) { t in
                        Button { state.setTopic(file, t.slug) } label: { Label(t.name, systemImage: TopicStyle.of(t.slug).symbol) }
                            .disabled(t.slug == file.topic && !file.isInInbox)
                    }
                }
                Section {
                    Button { state.undo(file) } label: {
                        Label("Put back in \(Paths.folderName(of: file.origPath))", systemImage: "arrow.uturn.backward")
                    }
                }
            } label: { Label("Change", systemImage: "arrow.triangle.swap") }
                .fixedSize()
                .help("Choose a different topic or put the file back")
        }
        .disabled(state.runningCommand != nil)
    }
}
