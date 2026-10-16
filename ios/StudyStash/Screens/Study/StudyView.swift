import SwiftUI

/// Flashcards and a quiz made from one lecture by the library's AI (from its notes, as Ask reads them), kept on the
/// phone so they open at once next time.
struct StudyDeck: Codable, Sendable {
    struct Card: Codable, Hashable, Sendable { var front: String; var back: String }
    struct Question: Codable, Hashable, Sendable { var question: String; var choices: [String]; var answer: Int; var why: String? }
    var cards: [Card]
    var quiz: [Question]

    /// The deck in an answer: the first JSON object in it, read leniently (the AI may wrap it in prose or a code fence).
    static func parse(_ text: String) -> StudyDeck? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        guard let deck = try? JSONDecoder().decode(StudyDeck.self, from: Data(text[start...end].utf8)) else { return nil }
        let quiz = deck.quiz.filter { $0.choices.count >= 2 && $0.choices.indices.contains($0.answer) }
        let cards = deck.cards.filter { !$0.front.isEmpty && !$0.back.isEmpty }
        return cards.isEmpty && quiz.isEmpty ? nil : StudyDeck(cards: cards, quiz: quiz)
    }

    static func prompt(_ title: String) -> String {
        """
        Make study material from the lecture "\(title)": 12 flashcards on its key ideas, terms and formulas, and 8 \
        multiple-choice questions that test understanding, not trivia. Reply with ONLY this JSON, nothing before or after:
        {"cards":[{"front":"question or term","back":"short answer"}],"quiz":[{"question":"...","choices":["A","B","C","D"],"answer":0,"why":"one sentence"}]}
        "answer" is the index of the right choice.
        """
    }
}

struct StudyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let lectureID: String
    let title: String

    enum Mode: String, CaseIterable { case cards = "Flashcards", quiz = "Quiz" }
    @State private var mode: Mode = DebugLaunch.studyQuiz ? .quiz : .cards
    @State private var deck: StudyDeck?
    @State private var making = false
    @State private var problem: String?

    private var cacheKey: String { "study:\(lectureID)" }

    var body: some View {
        NavigationStack {
            Group {
                if let deck {
                    VStack(spacing: 0) {
                        Picker("Mode", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                        switch mode {
                        case .cards: FlashcardsView(cards: deck.cards)
                        case .quiz: QuizView(questions: deck.quiz)
                        }
                    }
                } else if making {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("Making flashcards and a quiz from your notes…").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Couldn't make them", systemImage: "rectangle.on.rectangle.slash")
                    } description: {
                        Text(problem ?? "")
                    } actions: {
                        Button("Try again") { Task { await make() } }.buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if deck != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Make new ones", systemImage: "arrow.clockwise") { Task { await make() } }.disabled(making)
                    }
                }
            }
        }
        .task {
            if let saved = ResponseCache.shared.read(cacheKey, as: StudyDeck.self) { deck = saved } else { await make() }
        }
    }

    private func make() async {
        guard let api = app.api else { return }
        making = true
        problem = nil
        deck = nil
        defer { making = false }
        var text = ""
        do {
            for try await e in try await api.ask(StudyDeck.prompt(title), lecture: lectureID) {
                switch e {
                case .text(let t): text += t
                case .answer(let t): text = t
                case .done(let r): if !r.answer.isEmpty { text = r.answer }
                case .error(_, let d): problem = d
                }
            }
        } catch {
            problem = (error as? APIError)?.detail ?? "Couldn't reach your library."
        }
        if let d = StudyDeck.parse(text) {
            deck = d
            ResponseCache.shared.write(cacheKey, d)
        } else if problem == nil {
            problem = "The AI's answer wasn't flashcards. Try again."
        }
    }
}

/// Cards to flip (tap) and swipe through: right if you knew it, left to see it again.
private struct FlashcardsView: View {
    let cards: [StudyDeck.Card]
    @State private var queue: [StudyDeck.Card] = []
    @State private var flipped = false
    @State private var drag: CGSize = .zero
    @State private var known = 0

    var body: some View {
        VStack(spacing: 18) {
            Text(queue.isEmpty ? "Done" : "\(known) known · \(queue.count) to go").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            ZStack {
                if let card = queue.first {
                    ZStack {
                        face(card.front, label: "Question").opacity(flipped ? 0 : 1)
                        face(card.back, label: "Answer").opacity(flipped ? 1 : 0).rotation3DEffect(.degrees(180), axis: (0, 1, 0))
                    }
                    .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0))
                    .offset(drag)
                    .rotationEffect(.degrees(Double(drag.width) / 22))
                    .gesture(DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { v in
                            if abs(v.translation.width) > 110 { next(knew: v.translation.width > 0) } else { withAnimation(.spring) { drag = .zero } }
                        })
                    .onTapGesture { withAnimation(.spring(duration: 0.4)) { flipped.toggle() } }
                    .id(card)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(.green.gradient)
                        Text("You went through all \(cards.count)").font(.app(.docTitle))
                        Button("Go again") { reset() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            if !queue.isEmpty {
                HStack(spacing: 40) {
                    Button { next(knew: false) } label: { Label("Again", systemImage: "arrow.uturn.left").frame(minWidth: 100) }
                        .buttonStyle(.bordered).tint(.orange)
                    Button { next(knew: true) } label: { Label("Knew it", systemImage: "checkmark").frame(minWidth: 100) }
                        .buttonStyle(.borderedProminent).tint(.green)
                }
                .controlSize(.large)
            }
        }
        .padding(20)
        .onAppear(perform: reset)
    }

    private func face(_ text: String, label: String) -> some View {
        VStack(spacing: 14) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(text).font(label == "Question" ? .app(.docTitle) : .app(.lede)).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 520, minHeight: 300)
        .background(.surfaceSunken, in: .rect(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }

    private func next(knew: Bool) {
        guard let card = queue.first else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring) {
            queue.removeFirst()
            if knew { known += 1 } else { queue.append(card) }
            flipped = false
            drag = .zero
        }
    }

    private func reset() {
        queue = cards.shuffled()
        known = 0
        flipped = false
    }
}

/// One question at a time: pick, see if it's right and why, then the next; the score at the end.
private struct QuizView: View {
    let questions: [StudyDeck.Question]
    @State private var index = 0
    @State private var picked: Int?
    @State private var score = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if index < questions.count {
                    let q = questions[index]
                    Text("Question \(index + 1) of \(questions.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    Text(q.question).font(.app(.docTitle))
                    ForEach(Array(q.choices.enumerated()), id: \.offset) { i, choice in
                        Button {
                            guard picked == nil else { return }
                            picked = i
                            if i == q.answer { score += 1 }
                            UINotificationFeedbackGenerator().notificationOccurred(i == q.answer ? .success : .error)
                        } label: {
                            HStack {
                                Text(choice).multilineTextAlignment(.leading)
                                Spacer()
                                if let picked, i == q.answer { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                else if picked == i { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                            }
                            .padding(14)
                            .background(.surfaceSunken, in: .rect(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(picked != nil && i == q.answer ? Color.green : picked == i ? .red : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    if picked != nil {
                        if let why = q.why, !why.isEmpty { Text(why).font(.callout).foregroundStyle(.secondary) }
                        Button(index + 1 < questions.count ? "Next question" : "See my score") {
                            withAnimation { index += 1; picked = nil }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("\(score) / \(questions.count)").font(.system(size: 56, weight: .bold, design: .rounded))
                        Text(score == questions.count ? "Perfect." : score * 2 >= questions.count ? "Nice work." : "Worth another look at the notes.")
                            .font(.title3).foregroundStyle(.secondary)
                        Button("Try again") { index = 0; score = 0; picked = nil }.buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }
}
