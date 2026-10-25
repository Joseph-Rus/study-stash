import SwiftUI

// Which AI answers Ask, shown by its own mark, as the desktop shows it (Assets/Brands, Controls/Icon.cs): the marks are
// their owners' (Anthropic, OpenAI, Google, Ollama), downloaded unchanged and never recoloured or redrawn, shown only to
// say which product answers. While it thinks, each moves the way its own app's does: Claude's spark turns and pulses,
// ChatGPT's dot breathes, Gemini's star turns with a soft shimmer, Ollama's llama bobs. Reduce Motion keeps them still.

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

/// The answering AI thinking, as its own app shows it; three dots in the subtle ink when it isn't known yet.
struct ThinkingMark: View {
    var engine: AskEngine?
    var size: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var still
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let s = size * scale
        Group {
            if still {
                mark(s, t: 0, moving: false)
            } else {
                TimelineView(.animation) { context in
                    mark(s, t: context.date.timeIntervalSinceReferenceDate, moving: true)
                }
            }
        }
        .frame(width: s, height: s)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func mark(_ s: CGFloat, t: Double, moving: Bool) -> some View {
        switch engine {
        case .claude:
            // The spark turns, a quarter at a time with a soft settle, and breathes.
            let turn = t / 0.9
            let step = floor(turn), within = turn - step
            let eased = within < 0.6 ? 0.5 - 0.5 * cos(within / 0.6 * .pi) : 1
            BrandMark(.claude, size: s * 0.92)
                .rotationEffect(.degrees(moving ? (step + eased) * 45 : 0))
                .scaleEffect(moving ? 0.86 + 0.14 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.8)) : 1)
        case .chatgpt:
            // ChatGPT's filled dot, breathing.
            let breath = 0.5 + 0.5 * sin(t * 2 * .pi / 1.4)
            Circle().fill(.ink)
                .frame(width: s * 0.62, height: s * 0.62)
                .scaleEffect(moving ? 0.7 + 0.3 * breath : 1)
        case .gemini:
            // The star turns slowly and shimmers.
            BrandMark(.gemini, size: s * 0.92)
                .rotationEffect(.degrees(moving ? t.truncatingRemainder(dividingBy: 3.6) / 3.6 * 360 : 0))
                .scaleEffect(moving ? 0.88 + 0.12 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.6)) : 1)
                .opacity(moving ? 0.72 + 0.28 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.2)) : 1)
        case .ollama:
            // The llama bobs, with a little tilt.
            let bob = sin(t * 2 * .pi / 1.1)
            BrandMark(.ollama, size: s * 0.95)
                .offset(y: moving ? -2.5 * abs(bob) : 0)
                .rotationEffect(.degrees(moving ? 4 * sin(t * 2 * .pi / 2.2) : 0), anchor: .bottom)
        case nil:
            HStack(spacing: s * 0.12) {
                ForEach(0..<3) { i in
                    let phase = 0.5 + 0.5 * sin((t - Double(i) * 0.18) * 2 * .pi / 1.2)
                    Circle().fill(.inkSubtle)
                        .frame(width: s * 0.22, height: s * 0.22)
                        .opacity(moving ? 0.35 + 0.65 * phase : 1)
                }
            }
        }
    }
}
