import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Page layout

/// Large title with an explanatory sentence below – every page first says what it is for.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.titleFont)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Scrolling page with a title, limited content width and page background.
struct PageScroll<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.gap) {
                PageHeader(title, subtitle: subtitle) { trailing }
                    .padding(.bottom, 4)
                content
            }
            .frame(maxWidth: DS.contentWidth, alignment: .leading)
            .padding(DS.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(DS.page)
    }
}

extension PageScroll where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    let detail: String?
    let trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(DS.sectionFont)
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 8)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

/// Heading inside a card.
struct CardTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Icons & labels

/// Colored icon in a rounded square – the visual marker for topics and states.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 34
    var round = false

    var body: some View {
        RoundedRectangle(cornerRadius: round ? size / 2 : size * 0.29, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct TopicPill: View {
    let slug: String?
    let name: String
    var chevron = false

    var body: some View {
        let style = TopicStyle.of(slug)
        HStack(spacing: 5) {
            Image(systemName: style.symbol).foregroundStyle(style.color).imageScale(.small)
            Text(name).foregroundStyle(.primary)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(style.color.opacity(0.14), in: Capsule())
    }
}

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.fill, in: Capsule())
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false
    var size: CGFloat = 8
    @ViewState private var ring = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .stroke(color.opacity(0.7), lineWidth: 1.5)
                    .scaleEffect(ring ? 2.4 : 1)
                    .opacity(ring ? 0 : 1)
                    .animation(ring ? .easeOut(duration: 1.3).repeatForever(autoreverses: false) : .default, value: ring)
            }
            Circle().fill(color)
        }
        .frame(width: size, height: size)
        .task(id: pulsing) {
            ring = false
            try? await Task.sleep(for: .milliseconds(30))
            ring = pulsing
        }
    }
}

/// The AI's confidence in words instead of percent – the number is in the tooltip.
struct ConfidenceLabel: View {
    let value: Double
    let threshold: Double

    var body: some View {
        let unsure = value < threshold
        HStack(spacing: 5) {
            Circle().fill(unsure ? DS.attention : DS.ok).frame(width: 7, height: 7)
            Text(unsure ? "Unsure" : (value >= 0.9 ? "Very confident" : "Fairly confident"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("The AI was \(Int((value * 100).rounded()))% confident")
    }
}

/// Notice row for anything that needs attention but isn't the main thing.
struct Notice: View {
    let text: String
    var systemImage = "exclamationmark.triangle.fill"
    var tint: Color = DS.attention
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .card(padding: 12, radius: 12, tint: tint)
    }
}

struct EmptyState: View {
    let symbol: String
    var color: Color = DS.ok
    let title: String
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            IconBadge(symbol: symbol, color: color, size: 60, round: true)
                .padding(.bottom, 4)
            Text(title).font(DS.heroFont)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Filters

struct FilterChip: Identifiable, Hashable {
    let id: String?
    let title: String
    let count: Int
    var symbol: String?
    var color: Color = DS.accent
}

/// Horizontal topic bar: one click filters, “All” clears the filter.
struct FilterChips: View {
    let chips: [FilterChip]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let on = chip.id == selection
                    Button { selection = chip.id } label: {
                        HStack(spacing: 6) {
                            if let symbol = chip.symbol {
                                Image(systemName: symbol)
                                    .foregroundStyle(on ? Color.white : chip.color)
                                    .imageScale(.small)
                            }
                            Text(chip.title)
                            Text(chip.count.formatted(Format.integer))
                                .monospacedDigit()
                                .foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary)
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(on ? AnyShapeStyle(chip.color.gradient) : AnyShapeStyle(DS.surface), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.10), lineWidth: 0.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.pagePadding)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Progress & metrics

struct ProgressBar: View {
    /// `nil` = duration unknown
    let value: Double?
    var tint: Color = DS.accent
    var height: CGFloat = 6

    var body: some View {
        if let value {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(tint.gradient).frame(width: max(height, geo.size.width * min(1, max(0, value))))
                }
            }
            .frame(height: height)
            .animation(.snappy, value: value)
        } else {
            ProgressView().progressViewStyle(.linear).tint(tint)
        }
    }
}

/// The Mac's memory: the AI model's share in color, the rest in gray.
struct MemoryBar: View {
    let used: Int64
    let model: Int64
    let total: Int64
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                let w = geo.size.width
                let usedW = total > 0 ? w * CGFloat(used) / CGFloat(total) : 0
                let modelW = total > 0 ? w * CGFloat(min(model, used)) / CGFloat(total) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(Color.primary.opacity(0.22)).frame(width: usedW)
                    Capsule().fill(DS.accent.gradient).frame(width: modelW)
                }
            }
            .frame(height: compact ? 4 : 8)
            if !compact {
                HStack(spacing: 14) {
                    legend(DS.accent, "AI \(Format.bytes(model))")
                    legend(Color.primary.opacity(0.22), "Everything else \(Format.bytes(max(0, used - model)))")
                    Spacer()
                    Text("\(Format.bytes(max(0, total - used))) free").foregroundStyle(.secondary)
                }
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("i", i), y: .value("v", v))
                .interpolationMethod(.monotone)
                .foregroundStyle(.linearGradient(colors: [DS.accent.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("i", i), y: .value("v", v))
                .interpolationMethod(.monotone)
                .foregroundStyle(DS.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

/// Labeled “what – value” row for detail cards. Use inside a `Grid`.
struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value).monospacedDigit().lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }
}

// MARK: - Settings rows

/// Icon, title and an explanatory sentence – on the left of every settings row.
struct SettingLabel: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
        }
    }
}

/// One “what – explanation – control” row. Several of them in a `SettingsCard` form a block.
struct SettingRow<Control: View>: View {
    let symbol: String
    let title: String
    let text: String
    let control: Control

    init(_ symbol: String, _ title: String, _ text: String, @ViewBuilder control: () -> Control) {
        self.symbol = symbol
        self.title = title
        self.text = text
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingLabel(symbol: symbol, title: title, text: text)
            control
        }
        .padding(.vertical, 12)
    }
}

/// Toggle row with an explanation that depends on the state.
struct SettingToggle: View {
    let symbol: String
    let title: String
    let on: String
    let off: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { SettingLabel(symbol: symbol, title: title, text: isOn ? on : off) }
            .toggleStyle(.switch)
            .padding(.vertical, 12)
    }
}

/// Card that stacks settings rows. Put a `Divider()` between each pair of rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.vertical, -8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

// MARK: - Collapsible section

/// Technical details stay collapsed until someone wants to see them.
struct Collapsible<Content: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let content: Content
    @ViewState private var open: Bool

    init(_ title: String, detail: String, systemImage: String, startsOpen: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.content = content()
        _open = ViewState(initialValue: startsOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { withAnimation(.snappy(duration: 0.22)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.body.weight(.semibold))
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Files

enum FileIcon {
    private static var cache: [String: NSImage] = [:]

    /// System icon by file type – without reading the file itself (no folder access needed).
    @MainActor static func image(for ext: String) -> NSImage {
        if let hit = cache[ext] { return hit }
        let image = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        cache[ext] = image
        return image
    }
}

struct FileIconView: View {
    let ext: String
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: FileIcon.image(for: ext))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// “Choose topic” menu – for suggestions, the inbox and files that are already sorted.
struct TopicMenu<L: View>: View {
    @Environment(AppState.self) private var state
    let file: FileItem
    let label: L

    init(file: FileItem, @ViewBuilder label: () -> L) {
        self.file = file
        self.label = label()
    }

    var body: some View {
        Menu {
            ForEach(state.config.topics) { t in
                Button { state.setTopic(file, t.slug) } label: {
                    Label(t.name, systemImage: TopicStyle.of(t.slug).symbol)
                }
                .disabled(t.slug == file.topic && file.status == "moved" && !file.isInInbox)
            }
        } label: { label }
            .disabled(state.runningCommand != nil)
    }
}

/// Wrapping layout for keywords (Layout protocol, no macros needed).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
