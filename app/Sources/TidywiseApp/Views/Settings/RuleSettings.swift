import SwiftUI

/// “How does Tidywise sort?” – wait time, automation, caution, interval, skipped file types.
struct RuleSettings: View {
    @Binding var config: TidywiseConfig
    /// Show the interval only where it belongs (in Settings, not in setup).
    var showsInterval = true
    @ViewState private var extensions = ""

    private static let cautionLevels: [(value: Double, title: String)] = [(0.8, "Careful"), (0.6, "Balanced"), (0.4, "Generous")]
    private static let intervals = [5, 15, 30, 60]

    var body: some View {
        SettingsCard {
            SettingRow("hourglass", "When to sort",
                       "A file stays put until it has been unchanged for this long. That way nothing you're working on disappears.") {
                Picker("When to sort", selection: $config.minAgeMinutes) {
                    ForEach(waitChoices, id: \.minutes) { Text($0.title).tag($0.minutes) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            SettingToggle(symbol: "wand.and.stars", title: "Move automatically",
                          on: "On: Tidywise moves clear cases itself. Only unclear ones end up under “Review”.",
                          off: "Off: Tidywise only makes suggestions. You confirm them under “Review”.",
                          isOn: $config.autoApply)
            Divider()
            SettingRow("dial.medium", "When unsure", cautionText) {
                Picker("When unsure", selection: caution) {
                    ForEach(Self.cautionLevels, id: \.value) { Text($0.title).tag($0.value) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if showsInterval {
                Divider()
                SettingRow("clock.arrow.circlepath", "How often to check",
                           "While Tidywise is open – even if only the icon in the menu bar is showing.") {
                    Picker("How often to check", selection: $config.intervalMinutes) {
                        ForEach(intervalChoices, id: \.self) { Text(Self.intervalTitle($0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Divider()
            SettingRow("nosign", "File types to skip",
                       "Extensions Tidywise never touches – for example half-finished downloads. Separate with commas.") {
                TextField("e.g. .tmp, .part", text: $extensions)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(commitExtensions)
            }
        }
        .onAppear { extensions = config.skipExtensions.joined(separator: ", ") }
        .onChange(of: config.skipExtensions) { extensions = config.skipExtensions.joined(separator: ", ") }
        .onDisappear(perform: commitExtensions)
    }

    /// If the configuration holds a value the list doesn't know (entered by hand), it stays selectable.
    private var waitChoices: [(minutes: Double, title: String)] {
        var all = WaitChoice.all
        if !all.contains(where: { $0.minutes == config.minAgeMinutes }) {
            all.append((config.minAgeMinutes, "After \(WaitChoice.text(minutes: config.minAgeMinutes))"))
        }
        return all.sorted { $0.minutes < $1.minutes }
    }

    private var intervalChoices: [Int] {
        (Self.intervals + [config.intervalMinutes]).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.sorted()
    }

    private static func intervalTitle(_ minutes: Int) -> String {
        minutes == 60 ? "Every hour" : "Every \(minutes) minutes"
    }

    /// Three levels instead of a number; behind them is the model's minimum confidence.
    private var caution: Binding<Double> {
        Binding(
            get: { Self.cautionLevels.min { abs($0.value - config.minConfidence) < abs($1.value - config.minConfidence) }!.value },
            set: { config.minConfidence = $0 }
        )
    }

    private var cautionText: String {
        switch caution.wrappedValue {
        case 0.8: "Careful: Only what the AI is very sure about gets a topic. The rest waits in the inbox."
        case 0.4: "Generous: The AI sorts even when in doubt. Fewer questions, but it's wrong more often."
        default: "Balanced: What the AI is fairly sure about gets a topic. The rest waits in the inbox."
        }
    }

    private func commitExtensions() {
        let parsed = extensions.split(whereSeparator: { ", ;".contains($0) })
            .map { $0.lowercased() }
            .map { $0.hasPrefix(".") ? $0 : "." + $0 }
        let unique = parsed.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if unique != config.skipExtensions { config.skipExtensions = unique }
    }
}
