import Foundation

/// The AI models Wissen offers to choose from. Any other Ollama model works too (the “Another model” field).
/// Offering a new model = adding a line here.
struct ModelOption: Identifiable, Hashable {
    /// Name as used with `ollama pull`.
    let tag: String
    let title: String
    let family: String
    let text: String
    /// Download size in bytes (for display before Ollama reports the real size).
    let downloadBytes: Int64
    /// With this much memory or more, the model runs comfortably alongside normal work.
    let comfortableRAMGB: Int
    var id: String { tag }
}

enum ModelCatalog {
    static let small = ModelOption(
        tag: "gemma4:e2b-it-qat", title: "Small", family: "Gemma 4 E2B",
        text: "Light and fast. A bit more often unsure with tricky files.",
        downloadBytes: 4_300_000_000, comfortableRAMGB: 8)
    static let standard = ModelOption(
        tag: "gemma4:e4b-it-qat", title: "Standard", family: "Gemma 4 E4B",
        text: "A good mix of speed and accuracy. Wissen is tuned for this one.",
        downloadBytes: 6_100_000_000, comfortableRAMGB: 16)
    static let large = ModelOption(
        tag: "gemma4:12b-it-qat", title: "Large", family: "Gemma 4 12B",
        text: "The most accurate, but slower and needs the most memory.",
        downloadBytes: 7_200_000_000, comfortableRAMGB: 24)

    static let all = [small, standard, large]

    static func option(_ tag: String) -> ModelOption? { all.first { $0.tag == tag } }

    /// Recommendation based on installed memory: under 16 GB the small model, otherwise the standard one.
    static func recommended(ramBytes: Int64) -> ModelOption {
        ramBytes < 15 * 1_073_741_824 ? small : standard
    }
}
