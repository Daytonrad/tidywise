import SwiftUI

/// Topics are the folders Tidywise sorts into. This is where you create, rename and describe them.
struct TopicSettings: View {
    @Environment(AppState.self) private var state
    @Binding var config: TidywiseConfig
    /// Slug of the topic currently being edited; `TopicSettings.newID` for a new one.
    @ViewState private var editing: String?
    @ViewState private var draft = Topic(slug: "", name: "")
    @ViewState private var deleting: Topic?

    static let newID = "\u{0}new"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(title: "Topics", systemImage: "square.grid.2x2")
                Spacer()
                Button { startNew() } label: { Label("Add topic", systemImage: "plus") }
                    .disabled(editing != nil)
            }
            Text("Every topic is a folder. The AI reads the description for every file – the more specific it is, the better Tidywise gets it right.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if editing == Self.newID {
                TopicEditor(topic: $draft, isNew: true, onSave: saveDraft, onCancel: { editing = nil })
            }
            VStack(spacing: 2) {
                ForEach(config.topics) { topic in
                    if editing == topic.slug {
                        TopicEditor(topic: $draft, isNew: false, onSave: saveDraft, onCancel: { editing = nil })
                            .padding(.vertical, 6)
                    } else {
                        row(topic)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .animation(.snappy(duration: 0.2), value: editing)
        .alert("Remove “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Remove", role: .destructive) {
                if let slug = deleting?.slug { config.topics.removeAll { $0.slug == slug } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    private func row(_ topic: Topic) -> some View {
        let files = fileCount(topic.slug)
        return HStack(spacing: 12) {
            IconBadge(symbol: TopicStyle(topic).symbol, color: TopicStyle(topic).color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(topic.name).font(.body.weight(.medium)).lineLimit(1)
                    if files > 0 {
                        Text(files == 1 ? "1 file" : "\(files.formatted(Format.integer)) files").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Text(topic.description.isEmpty ? "No description yet – the AI then only guesses from the name." : topic.description)
                    .font(.callout)
                    .foregroundStyle(topic.description.isEmpty ? AnyShapeStyle(DS.attention) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Button { start(topic) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Edit “\(topic.name)”")
                .disabled(editing != nil)
            if topic.isFallback {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                    .help("The catch-all topic always stays – this is where everything goes that doesn't fit anywhere else.")
            } else {
                Button { deleting = topic } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .frame(width: 18)
                    .help("Remove “\(topic.name)”")
                    .disabled(editing != nil)
            }
        }
        .foregroundStyle(.primary)
        .hoverHighlight()
    }

    private func fileCount(_ slug: String) -> Int {
        state.moved.filter { $0.topic == slug && !$0.isInInbox }.count
    }

    private var deleteMessage: String {
        guard let topic = deleting else { return "" }
        let files = fileCount(topic.slug)
        if files == 0 { return "Tidywise will then stop sorting anything into this topic." }
        return "\(files == 1 ? "1 file stays" : "\(files) files stay") in the folder “\(topic.slug)” – nothing is deleted. Tidywise just won't sort anything new there."
    }

    private func startNew() {
        draft = Topic(slug: "", name: "", description: "", symbol: "folder.fill", color: unusedColor)
        editing = Self.newID
    }

    private func start(_ topic: Topic) {
        draft = topic
        editing = topic.slug
    }

    private func saveDraft() {
        var topic = draft
        topic.name = topic.name.trimmingCharacters(in: .whitespaces)
        topic.description = topic.description.trimmingCharacters(in: .whitespacesAndNewlines)
        var topics = config.topics
        if editing == Self.newID {
            topic.slug = Self.uniqueSlug(for: topic.name, taken: Set(topics.map(\.slug)))
            // The catch-all topic stays at the end of the list.
            let index = topics.firstIndex(where: \.isFallback) ?? topics.endIndex
            topics.insert(topic, at: index)
        } else if let index = topics.firstIndex(where: { $0.slug == topic.slug }) {
            topics[index] = topic
        }
        config.topics = topics
        editing = nil
    }

    /// A color no topic has yet – so new topics stand out right away.
    private var unusedColor: String {
        let used = Set(config.topics.map(\.color))
        return TopicColor.all.map(\.name).first { !used.contains($0) && $0 != "gray" } ?? "blue"
    }

    /// Folder name from the topic name, exactly as the CLI would build it: “Küche & Rezepte” → “kueche-rezepte”.
    static func uniqueSlug(for name: String, taken: Set<String>) -> String {
        var s = name.lowercased()
        for (a, b) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] { s = s.replacingOccurrences(of: a, with: b) }
        let parts = s.split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
        var base = String(parts.joined(separator: "-").prefix(40))
        while base.hasSuffix("-") { base.removeLast() }
        if base.isEmpty { base = "topic" }
        var slug = base
        var n = 2
        while taken.contains(slug) || ["new", "neu", "_inbox", "_private", "_privat"].contains(slug) {
            slug = "\(base)-\(n)"
            n += 1
        }
        return slug
    }
}

/// Form for a topic: name, description, icon, color.
struct TopicEditor: View {
    @Binding var topic: Topic
    let isNew: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var nameMissing: Bool { topic.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(symbol: topic.symbol, color: TopicColor.color(topic.color), size: 44)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name, e.g. “Home”", text: $topic.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.weight(.medium))
                        .onSubmit { if !nameMissing { onSave() } }
                    TextField("What belongs here? E.g. “lease, utilities, repairs, furniture”", text: $topic.description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Color").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    ForEach(TopicColor.all, id: \.name) { entry in
                        Button { topic.color = entry.name } label: {
                            Circle()
                                .fill(entry.color.gradient)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if topic.color == entry.name {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                                .padding(2)
                                .overlay(Circle().strokeBorder(topic.color == entry.name ? entry.color : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .help(TopicColor.title(entry.name))
                        .accessibilityLabel(TopicColor.title(entry.name))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(TopicSymbols.all, id: \.self) { symbol in
                        let on = topic.symbol == symbol
                        Button { topic.symbol = symbol } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(on ? Color.white : Color.secondary)
                                .frame(width: 34, height: 30)
                                .background(on ? AnyShapeStyle(TopicColor.color(topic.color).gradient) : AnyShapeStyle(DS.fill),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text(isNew ? "The folder gets the topic's name." : "Folder: \(topic.slug) – stays the same when you rename the topic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(nameMissing)
            }
        }
        .padding(14)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.accent.opacity(0.35), lineWidth: 1))
    }
}

/// For setup: select and deselect topics as tiles, add your own.
struct TopicChooser: View {
    @Binding var config: TidywiseConfig
    /// All topics available to choose from (suggestions plus your own), in a fixed order.
    @ViewState private var pool: [Topic] = []
    @ViewState private var adding = false
    @ViewState private var draft = Topic(slug: "", name: "")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                ForEach(pool.filter { !$0.isFallback }) { tile($0) }
            }
            if adding {
                TopicEditor(topic: $draft, isNew: true, onSave: add, onCancel: { adding = false })
            } else {
                Button {
                    draft = Topic(slug: "", name: "", symbol: "star.fill", color: "indigo")
                    adding = true
                } label: { Label("Your own topic", systemImage: "plus") }
            }
        }
        .onAppear { if pool.isEmpty { pool = config.topics } }
        .animation(.snappy(duration: 0.2), value: adding)
    }

    private func tile(_ topic: Topic) -> some View {
        let on = config.topics.contains { $0.slug == topic.slug }
        return Button { toggle(topic) } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: TopicStyle(topic).symbol, color: on ? TopicStyle(topic).color : .gray.opacity(0.5), size: 32)
                Text(topic.name).font(.callout.weight(.medium)).lineLimit(1).foregroundStyle(on ? .primary : .secondary)
                Spacer(minLength: 4)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(on ? AnyShapeStyle(DS.accent) : AnyShapeStyle(.tertiary))
            }
            .padding(10)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? DS.accent.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: on ? 1 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(topic.description)
    }

    private func toggle(_ topic: Topic) {
        if config.topics.contains(where: { $0.slug == topic.slug }) {
            config.topics.removeAll { $0.slug == topic.slug }
        } else {
            // Keep the pool's order
            let chosen = Set(config.topics.map(\.slug)).union([topic.slug])
            config.topics = pool.filter { chosen.contains($0.slug) }
        }
    }

    private func add() {
        var topic = draft
        topic.name = topic.name.trimmingCharacters(in: .whitespaces)
        topic.slug = TopicSettings.uniqueSlug(for: topic.name, taken: Set(pool.map(\.slug)))
        let index = pool.firstIndex(where: \.isFallback) ?? pool.endIndex
        pool.insert(topic, at: index)
        let chosen = Set(config.topics.map(\.slug)).union([topic.slug])
        config.topics = pool.filter { chosen.contains($0.slug) }
        adding = false
    }
}
