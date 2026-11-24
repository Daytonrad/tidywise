import AppKit
import SwiftUI

/// With the Command Line Tools (without Xcode), the macro plugin for SwiftUI's `@State` is missing.
/// The alias uses the classic property wrapper directly.
typealias ViewState = SwiftUI.State

// MARK: - Design tokens

/// Color rule: hue = topic. Green/orange/red = state. Accent (indigo) = “Tidywise is working” and the main action.
enum DS {
    static let pagePadding: CGFloat = 28
    static let gap: CGFloat = 16
    static let cardPadding: CGFloat = 18
    static let radius: CGFloat = 16
    static let innerRadius: CGFloat = 9
    /// Content isn't stretched endlessly in wide windows.
    static let contentWidth: CGFloat = 1040

    static let accent = Color.dynamic(light: NSColor(srgbRed: 0.33, green: 0.30, blue: 0.90, alpha: 1),
                                      dark: NSColor(srgbRed: 0.58, green: 0.56, blue: 1.00, alpha: 1))
    static let ok = Color.green
    static let attention = Color.orange
    static let problem = Color.red

    static let page = Color.dynamic(light: NSColor(srgbRed: 0.953, green: 0.955, blue: 0.965, alpha: 1),
                                    dark: NSColor(srgbRed: 0.105, green: 0.105, blue: 0.118, alpha: 1))
    static let surface = Color.dynamic(light: .white,
                                       dark: NSColor(srgbRed: 0.160, green: 0.160, blue: 0.178, alpha: 1))
    static let hairline = Color.primary.opacity(0.08)
    /// Subtle fill for chips, fields and bar backgrounds.
    static let fill = Color.primary.opacity(0.06)

    static let titleFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let heroFont = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let numberFont = Font.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()
    static let sectionFont = Font.system(size: 17, weight: .semibold, design: .rounded)
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
    }

    static func topic(_ slug: String?) -> Color { TopicStyle.of(slug).color }
}

// MARK: - Topics

/// Colors a topic can have. The names appear like this in the configuration.
enum TopicColor {
    static let all: [(name: String, color: Color)] = [
        ("blue", .blue),
        ("cyan", Color(red: 0.10, green: 0.60, blue: 0.82)),
        ("teal", .teal),
        ("mint", Color(red: 0.05, green: 0.68, blue: 0.60)),
        ("green", .green),
        ("yellow", Color(red: 0.93, green: 0.64, blue: 0.10)),
        ("orange", .orange),
        ("red", .red),
        ("pink", .pink),
        ("magenta", Color(red: 0.80, green: 0.35, blue: 0.75)),
        ("purple", .purple),
        ("indigo", .indigo),
        ("brown", .brown),
        ("slate", Color(red: 0.42, green: 0.52, blue: 0.68)),
        ("gray", .gray),
    ]

    static func color(_ name: String) -> Color { all.first { $0.name == name }?.color ?? .gray }

    /// Name of the color for tooltips and VoiceOver.
    static func title(_ name: String) -> String {
        ["blue": "Blue", "cyan": "Cyan", "teal": "Teal", "mint": "Mint", "green": "Green", "yellow": "Yellow",
         "orange": "Orange", "red": "Red", "pink": "Pink", "magenta": "Magenta", "purple": "Purple", "indigo": "Indigo",
         "brown": "Brown", "slate": "Slate", "gray": "Gray"][name] ?? name
    }
}

/// Icons to choose from for your own topics.
enum TopicSymbols {
    static let all = [
        "folder.fill", "doc.text.fill", "person.text.rectangle.fill", "eurosign.circle.fill", "briefcase.fill",
        "graduationcap.fill", "book.fill", "chevron.left.forwardslash.chevron.right", "shippingbox.fill", "photo.fill",
        "camera.fill", "film.fill", "music.note", "gamecontroller.fill", "cart.fill", "airplane", "car.fill",
        "house.fill", "heart.fill", "cross.case.fill", "fork.knife", "leaf.fill", "pawprint.fill", "figure.run",
        "bubble.left.and.bubble.right.fill", "envelope.fill", "newspaper.fill", "key.fill", "building.columns.fill",
        "hammer.fill", "paintbrush.fill", "lightbulb.fill", "globe.europe.africa.fill", "star.fill", "tray.fill",
    ]
}

struct TopicStyle {
    let color: Color
    let symbol: String

    /// Appearance of the topics from the configuration. Reset on every load (main thread only).
    private static var table: [String: TopicStyle] = [:]
    static var isEmpty: Bool { table.isEmpty }

    static func register(_ topics: [Topic]) {
        var next: [String: TopicStyle] = ["_inbox": .init(color: .orange, symbol: "questionmark.folder.fill")]
        for t in topics { next[t.slug] = TopicStyle(t) }
        table = next
    }

    init(color: Color, symbol: String) {
        self.color = color
        self.symbol = symbol
    }

    init(_ topic: Topic) {
        self.init(color: TopicColor.color(topic.color), symbol: topic.symbol.isEmpty ? "folder.fill" : topic.symbol)
    }

    static func of(_ slug: String?) -> TopicStyle {
        table[slug ?? ""] ?? TopicStyle(color: .gray, symbol: "folder.fill")
    }
}

// MARK: - Surfaces

extension View {
    /// Card: light surface with a fine border and soft shadow. The shadow is attached to the surface,
    /// not the content – otherwise text would cast a shadow too.
    func card(padding: CGFloat = DS.cardPadding, radius: CGFloat = DS.radius, tint: Color? = nil) -> some View {
        self.padding(padding)
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    shape.fill(DS.surface).shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    if let tint {
                        shape.fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.03)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    shape.strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.08 : 0.22), lineWidth: 0.5)
                }
            }
    }

    /// Recessed surface inside a card (code, log, metric).
    func well(padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.innerRadius, style: .continuous))
    }

    /// For pages that show a list instead of scrolling: fills the space but asks for nothing.
    /// Otherwise lists report their full content height as their ideal size – and the window column grows beyond the window.
    func pageFill() -> some View {
        frame(minWidth: 0, idealWidth: 700, maxWidth: .infinity, minHeight: 0, idealHeight: 500, maxHeight: .infinity, alignment: .topLeading)
    }

    func hoverHighlight(radius: CGFloat = DS.innerRadius) -> some View { modifier(HoverHighlight(radius: radius)) }

    /// The page title is shown large in the content; in the toolbar it would appear twice.
    @ViewBuilder func pageTitle(_ title: String) -> some View {
        if #available(macOS 15.0, *) {
            navigationTitle(title).toolbar(removing: .title)
        } else {
            navigationTitle(title)
        }
    }
}

struct HoverHighlight: ViewModifier {
    let radius: CGFloat
    @ViewState private var hover = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(hover ? DS.fill : .clear, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

/// Card that behaves like a button: lifts slightly on hover.
struct CardButtonStyle: ButtonStyle {
    var padding: CGFloat = DS.cardPadding

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, padding: padding)
    }

    private struct Inner: View {
        let configuration: Configuration
        let padding: CGFloat
        @ViewState private var hover = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padding)
                .background {
                    let shape = RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    ZStack {
                        shape.fill(DS.surface).shadow(color: .black.opacity(hover ? 0.10 : 0.05), radius: hover ? 12 : 8, y: hover ? 4 : 2)
                        shape.strokeBorder(Color.primary.opacity(hover ? 0.14 : 0.08), lineWidth: 0.5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(.snappy(duration: 0.18), value: hover)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}
