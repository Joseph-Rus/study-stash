import SwiftUI

// Which AI answers Ask, shown by its own mark, as the desktop shows it (Assets/Brands, Controls/Icon.cs): the marks are
// their owners' (Anthropic, OpenAI, Google, Ollama), downloaded unchanged and never recoloured or redrawn, shown only to
// say which product answers: small and still, in the header and under a finished answer. Never beside our own mark or
// loader: while it works, the s's hopping bits are the only thing moving and the AI is named in words.

/// The AI the library asks: Claude, ChatGPT (through Codex), Gemini or Ollama.
enum AskEngine: String, Codable, Sendable, CaseIterable {
    case claude, chatgpt, gemini, ollama

    /// From the library's id for it (`jobs.ask.provider`, an answer's `engine`): "claude", "codex", "gemini", "ollama".
    init?(id: String?) {
        switch id?.lowercased() {
        case "claude", "anthropic": self = .claude
        case "codex", "openai", "chatgpt": self = .chatgpt
        case "gemini", "google": self = .gemini
        case "ollama": self = .ollama
        default: return nil
        }
    }

    /// From the name an answer gave ("Claude", "ChatGPT", "Local model (Ollama)"), for a library that gave no id.
    init?(name: String?) {
        let n = name?.lowercased() ?? ""
        if n.contains("claude") { self = .claude }
        else if n.contains("chatgpt") || n.contains("codex") || n.contains("openai") || n.contains("gpt") { self = .chatgpt }
        else if n.contains("gemini") { self = .gemini }
        else if n.contains("ollama") || n.contains("llama") || n.contains("local model") { self = .ollama }
        else { return nil }
    }

    /// Its name as a student knows it.
    var name: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .gemini: "Gemini"
        case .ollama: "Ollama"
        }
    }

    /// Its mark in the asset catalog (Resources/Assets.xcassets/Brands): a light and a dark file where it's one ink.
    var asset: String { "brand-\(rawValue)" }
}

/// The AI answering Ask, as the library says (`GET /ai`, `jobs.ask.provider`) or, until it can, as the last answer
/// said. Kept on the phone, so the mark shows at once and offline.
@MainActor @Observable
final class AskEngineWatch {
    static let shared = AskEngineWatch()

    /// The AI that answers; nil until anything has said.
    private(set) var engine: AskEngine?
    @ObservationIgnored private var asked = false

    private init() {
        engine = ResponseCache.shared.read("ask-engine", as: AskEngine.self)
        #if DEBUG
        // `-ask-engine claude|codex|gemini|ollama` (with the sample classes): that one answers.
        if let id = DebugLaunch.value("-ask-engine") { engine = AskEngine(id: id) }
        #endif
    }

    /// Ask the library which AI answers, once a launch (a library that can't say keeps what was known).
    func refresh(_ api: APIClient) async {
        guard !asked else { return }
        asked = true
        guard let settings = try? await api.aiSettings(), let found = AskEngine(id: settings.jobs?["ask"]?.provider ?? settings.provider) else { return }
        heard(found)
    }

    /// An answer named the AI that wrote it.
    func heard(_ found: AskEngine?) {
        guard let found, found != engine else { return }
        engine = found
        ResponseCache.shared.write("ask-engine", found)
    }
}

/// An AI's own mark, unchanged, at `size` points.
struct BrandMark: View {
    var engine: AskEngine
    var size: CGFloat = 18
    @ScaledMetric private var scaled: CGFloat

    init(_ engine: AskEngine, size: CGFloat = 18, relativeTo style: Font.TextStyle = .body) {
        self.engine = engine
        self.size = size
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    var body: some View {
        Image(engine.asset)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: scaled, height: scaled)
            .accessibilityHidden(true)
    }
}
