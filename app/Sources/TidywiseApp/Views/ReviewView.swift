import SwiftUI

/// Everything that needs a decision: confirm suggestions, assign what's uncertain.
struct ReviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        PageScroll("Review", subtitle: subtitle) {
            if state.planned.isEmpty && state.inbox.isEmpty {
                EmptyState(symbol: "checkmark", title: "Nothing to review",
                           text: "New loose files show up here\(state.config.minAgeMinutes < 1 ? "" : " once they've been unchanged for \(state.config.minAgeText)"). Last checked \(Format.relative(state.lastRun)).",
                           actionTitle: state.canRunAI ? "Check for new files" : nil) { state.scan() }
                    .card(padding: 0)
            }

            if !state.planned.isEmpty {
                SectionHeader("Suggestions", detail: "\(state.planned.count)") {
                    if state.planned.count > 1 {
                        Button { state.applyAll() } label: { Label("Move all", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.runningCommand != nil)
                    }
                }
                ForEach(state.planned) { SuggestionCard(file: $0) }
            }

            if !state.inbox.isEmpty {
                SectionHeader("In the inbox", detail: "\(state.inbox.count)")
                Text("Tidywise wasn't sure about these. Choose a topic – the file then moves to the matching folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, -8)
                ForEach(state.inbox) { InboxCard(file: $0) }
            }

            if !state.config.autoApply, !state.planned.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb")
                    Text("Tired of confirming? In")
                    Button("Settings") { state.openSettings(.rules) }.buttonStyle(.link)
                    Text("you can let Tidywise move clear cases on its own.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
    }

    private var subtitle: String {
        if state.config.autoApply {
            return "Tidywise moves clear cases on its own. Only what's still open or unclear ends up here."
        }
        return "Tidywise suggests where a file belongs – nothing is moved until you agree."
    }
}

/// A suggestion read as a sentence: this file · from this folder → into this topic.
struct SuggestionCard: View {
    @Environment(AppState.self) private var state
    let file: FileItem

    private var goesToInbox: Bool {
        file.topic == "new" || file.topic == "neu" || file.confidence < state.config.minConfidence
            || !state.config.topics.contains(where: { $0.slug == file.topic })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FileIconView(ext: file.ext, size: 40)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    if !file.summary.isEmpty {
                        Text(file.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    Label(Paths.folderName(of: file.origPath), systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    TopicMenu(file: file) {
                        TopicPill(slug: goesToInbox ? "_inbox" : file.topic,
                                  name: goesToInbox ? "Inbox" : state.config.topicName(file.topic), chevron: true)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Choose a different topic")
                    ConfidenceLabel(value: file.confidence, threshold: state.config.minConfidence)
                    if let idea = file.newTopic, !idea.isEmpty {
                        TagChip(text: "Idea for a new topic: \(idea)")
                    }
                }
            }
            Spacer(minLength: 12)
            Button(goesToInbox ? "To inbox" : "Move") { state.apply([file.id]) }
                .controlSize(.large)
                .disabled(state.runningCommand != nil)
                .help(goesToInbox ? "The AI is unsure – the file goes to the inbox until you choose a topic"
                                  : "Move to “\(state.config.topicName(file.topic))”")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct InboxCard: View {
    @Environment(AppState.self) private var state
    let file: FileItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FileIconView(ext: file.ext, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                if !file.summary.isEmpty {
                    Text(file.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                if let idea = file.newTopic, !idea.isEmpty {
                    TagChip(text: "Idea for a new topic: \(idea)").padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            Button { state.reveal(file) } label: { Image(systemName: "magnifyingglass") }
                .help("Show in Finder")
            TopicMenu(file: file) { Text("Choose topic") }
                .fixedSize()
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
