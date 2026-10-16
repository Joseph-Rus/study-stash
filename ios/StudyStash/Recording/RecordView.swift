import SwiftUI

/// Recording a lecture: the lecture's page while it records, as the desktop's note page is (NotePage.axaml, the spec's
/// 5.5). At the top the recording's bar (its dot breathing, "Recording", the level, the time, Pause, and Stop in ink,
/// in a red outline); then where it's filed and when (the class is a button: the class picker), its title, and
/// Notes | Live transcript: the student's own notes, typed as it records, and what's been heard so far, written down
/// on this phone. Stop closes it and opens the lecture (its notes being written), or, when it couldn't be sent, the
/// recording on this phone.
struct RecordView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var recorder = Recorder.shared
    var startClass: String?

    enum Pane: Hashable { case notes, transcript }
    @State private var pane: Pane = DebugLaunch.value("-pane") == "transcript" ? .transcript : .notes
    @State private var confirmingDiscard = false
    @State private var writing: (id: String, title: String)?
    @State private var toast: String?
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .page()
                .foregroundStyle(.ink)
                .toolbar { toolbar }
                .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { recorder.discard(); dismiss() }
                } message: {
                    Text("What was said and what you typed are deleted from this phone.")
                }
                .toast($toast)
                // Write by hand: the notebook for this recording, pushed inside the recorder (never a second cover).
                .navigationDestination(isPresented: Binding(get: { writing != nil }, set: { if !$0 { writing = nil } })) {
                    if let w = writing {
                        HandwritingView(className: recorder.recording?.className, lecture: w, embedded: true)
                    }
                }
        }
        .presentationSizing(.page)
        .interactiveDismissDisabled(recorder.phase == .finishing)
        .task {
            if recorder.phase == .idle || isFailed {
                // An event's title is a working one ("Calculus II, Fri 16 Oct"): the library still names it.
                await recorder.start(className: startClass, title: app.recordTitle)
            }
            #if DEBUG
            // Pictures: `-pause-after <s>` pauses, `-stop-after <s>` stops (`-keep-on-phone` as if it couldn't be
            // sent); `-pick-class` opens the class picker (ClassPicker reads it).
            if let after = DebugLaunch.value("-pause-after").flatMap(Double.init) {
                try? await Task.sleep(for: .seconds(after))
                recorder.pause()
            }
            if let after = DebugLaunch.value("-stop-after").flatMap(Double.init) {
                try? await Task.sleep(for: .seconds(after))
                await stop()
            }
            #endif
        }
    }

    private var isFailed: Bool { if case .failed = recorder.phase { true } else { false } }

    /// Stop: the last words written down, kept, sent; then the recorder closes and the lecture opens (or, not sent,
    /// the recording on this phone).
    private func stop() async {
        guard let id = recorder.recording?.id else { return }
        typing = false
        await recorder.stop(api: app.api)
        var sent = RecordingStore.shared.recordings.first { $0.id == id }?.state == .sent
        #if DEBUG
        if DebugLaunch.flag("-keep-on-phone") { sent = false }
        #endif
        app.recordingFinished(id: id, sent: sent)
    }

    // MARK: the toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(icon: "expand_more") }
                .accessibilityLabel(recorder.isActive ? "Hide. It keeps recording" : "Close")
        }
        if recorder.isActive, let r = recorder.recording {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { mark() } label: { Image(icon: "bookmark") }
                    .accessibilityLabel("Mark this moment")
                    .disabled(recorder.phase == .finishing)
                Button { writing = (r.id, r.displayTitle) } label: { Image(icon: "edit_note") }
                    .accessibilityLabel("Write by hand")
                    .disabled(recorder.phase == .finishing)
                Menu {
                    Button("Discard recording", icon: "delete", role: .destructive) { confirmingDiscard = true }
                } label: { Image(icon: "more_horiz") }
                    .accessibilityLabel("More")
            }
        }
    }

    /// "This matters": the moment and its last words go in the notes ("Important at 12:04: …"), and a toast says so.
    private func mark() {
        let at = Format.clock(recorder.elapsed)
        recorder.mark()
        toast = "Marked \(at) in your notes"
    }

    // MARK: getting ready, couldn't, recording

    @ViewBuilder private var content: some View {
        switch recorder.phase {
        case .preparing(let words):
            VStack(alignment: .leading, spacing: 12) {
                ProgressView().tint(.inkSubtle)
                Text(words).textStyle(.lede).foregroundStyle(.inkMuted)
            }
            .padding(.horizontal, Space.pageCompact)
            .padding(.top, 24)
        case .failed(let words):
            CantRecord(words: words) { Task { await recorder.start(className: startClass, title: app.recordTitle) } }
        case .idle where recorder.recording == nil:
            // For a moment before it starts.
            ProgressView().tint(.inkSubtle).padding(.horizontal, Space.pageCompact).padding(.top, 24)
        default:
            recordingPage
        }
    }

    private var recordingPage: some View {
        let wide = sizeClass == .regular
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                RecordingBar(recorder: recorder) { Task { await stop() } }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                header
                if !wide {
                    TabStrip(selection: $pane, tabs: [(.notes, "Notes"), (.transcript, "Live transcript")])
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, wide ? 32 : Space.pageCompact)
            if wide {
                // An iPad: the notes and what's been said side by side.
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        paneTitle("Notes").padding(.horizontal, 32)
                        notesEditor
                    }
                    Rectangle().fill(.line).frame(width: 1).padding(.top, 18)
                    VStack(alignment: .leading, spacing: 0) {
                        paneTitle("Live transcript").padding(.horizontal, 24)
                        LiveTranscript(recorder: recorder, inset: 24)
                    }
                }
                .padding(.top, 18)
            } else {
                switch pane {
                case .notes: notesEditor
                case .transcript: LiveTranscript(recorder: recorder)
                }
            }
        }
        .frame(maxWidth: wide ? 1100 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private func paneTitle(_ words: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(words).textStyle(.tab).foregroundStyle(.ink).padding(.vertical, 10)
            Rule()
        }
    }

    /// Where it's filed (its class, the picker) and when; then its title, typed over to name it.
    private var header: some View {
        let r = recorder.recording
        let cls = r?.className
        let date = r.map { Recording.localISO($0.started) }
        let crumb = Nouns.capital(app.noun(of: cls)) + (date.map { ", " + Format.noteWhen($0, nil) } ?? "")
        let picker = ClassPicker(selection: Binding(get: { recorder.recording?.className },
                                                    set: { c in recorder.update { $0.className = c } }))
        return VStack(alignment: .leading, spacing: 8) {
            if sizeClass == .regular {
                HStack(spacing: 10) {
                    picker
                    Text(crumb).textStyle(.crumb).foregroundStyle(.inkMuted).lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    picker
                    Text(crumb).textStyle(.crumb).foregroundStyle(.inkMuted)
                }
            }
            TextField("Title", text: Binding(
                get: { r?.title ?? "" },
                set: { t in recorder.update { $0.title = t; $0.titleTyped = !t.isEmpty } }),
                prompt: Text(Nouns.untitled(folder: cls, date: date)).foregroundStyle(.ink),
                axis: .vertical)
                .textStyle(.docTitle)
                .foregroundStyle(.ink)
                .lineLimit(1...3)
                .submitLabel(.done)
                .accessibilityLabel("Title")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The student's own notes, as they type them: ink and a little heavy, as "What you wrote" is on the desktop. The
    /// cursor is in it from the start.
    private var notesEditor: some View {
        let empty = (recorder.recording?.notes ?? "").isEmpty
        let inset = sizeClass == .regular ? 32 : Space.pageCompact
        return TextEditor(text: Binding(get: { recorder.recording?.notes ?? "" }, set: { n in recorder.update { $0.notes = n } }))
            .focused($typing)
            .font(.atkinson(16, .semibold, relativeTo: .body))
            .lineSpacing(5)
            .foregroundStyle(.ink)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, inset - 5)
            .padding(.top, 10)
            .overlay(alignment: .topLeading) {
                if empty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your notes").font(.atkinson(16, .semibold, relativeTo: .body)).foregroundStyle(.inkSubtle)
                        Text(Self.hint).textStyle(.summary, italic: true).foregroundStyle(.inkSubtle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, inset)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Your notes")
            .accessibilityHint(Self.hint)
            .task {
                // The cursor in the notes, once the sheet has come up.
                try? await Task.sleep(for: .milliseconds(600))
                typing = true
            }
    }

    static let hint = "Write as much or as little as you like. When you stop, your notes are written up around what you typed."
}

// MARK: - The recording's bar

/// The desktop's recording bar (`.recbar`, role status): a red outline on the page's white, the panel's corners; the
/// dot breathing while it records, "Recording" (or "Paused", the dot still), the level, the time, then Pause (Resume)
/// and Stop, the ink button. After Stop, "Saving…". Where a phone is too narrow for all of it, Pause shows its icon
/// alone.
private struct RecordingBar: View {
    var recorder: Recorder
    var stop: () -> Void

    var body: some View {
        let phase = recorder.phase
        let word = phase == .finishing ? "Saving…" : phase == .paused ? "Paused" : "Recording"
        let time = Format.clock(recorder.elapsed)
        ViewThatFits(in: .horizontal) {
            row(word: word, time: time, pauseWords: true)
            row(word: word, time: time, pauseWords: false)
        }
        .padding(.vertical, 8)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .background(.surface, in: .rect(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(.record, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(word), \(time)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func row(word: String, time: String, pauseWords: Bool) -> some View {
        let phase = recorder.phase
        let paused = phase == .paused
        let finishing = phase == .finishing
        return HStack(spacing: 12) {
            PulseDot(pulsing: phase == .recording)
            Text(word).font(.atkinson(15, .bold, relativeTo: .body)).foregroundStyle(.ink).fixedSize()
            if phase == .recording { LevelBars(levels: recorder.levels) }
            Text(time).font(.atkinson(15, .medium, relativeTo: .body)).foregroundStyle(.inkMuted).fixedSize()
            Spacer(minLength: 4)
            Button {
                paused ? recorder.resume() : recorder.pause()
            } label: {
                if pauseWords {
                    Label(paused ? "Resume" : "Pause", icon: paused ? "play_arrow" : "pause")
                } else {
                    Icon(paused ? "play_arrow" : "pause", size: 16)
                }
            }
            .buttonStyle(.pill(small: true))
            .disabled(finishing)
            .accessibilityLabel(paused ? "Resume" : "Pause")
            Button(action: stop) {
                HStack(spacing: 8) {
                    if finishing {
                        ProgressView().controlSize(.mini).tint(.surface)
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(.surface).frame(width: 10, height: 10)
                    }
                    Text("Stop")
                }
            }
            .buttonStyle(.pill(small: true, ink: true))
            .disabled(finishing)
            .accessibilityLabel("Stop recording")
            .accessibilityHint("Its notes are written next")
        }
    }
}

/// The recording's dot: red, breathing while it records (not while paused, nor for someone who asked for less
/// motion), as the desktop's 1.6-second pulse.
struct PulseDot: View {
    var pulsing: Bool
    var size: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let dot = Circle().fill(.record).frame(width: size, height: size).accessibilityHidden(true)
        if pulsing && !still {
            dot.phaseAnimator([1.0, 0.35]) { view, opacity in view.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            dot
        }
    }
}

// MARK: - Couldn't record

/// The recorder couldn't start: the foundation's empty state in its words, and what to do. The microphone refused,
/// Open Settings goes straight to where it's turned on.
private struct CantRecord: View {
    var words: String
    var retry: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        let microphone = words.localizedCaseInsensitiveContains("microphone")
        VStack(alignment: .leading, spacing: 8) {
            Text("Can't record").textStyle(.h2).foregroundStyle(.ink)
            EmptyText(words)
            HStack(spacing: 10) {
                if microphone {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.pill(small: true, ink: true))
                }
                Button("Try again", action: retry).buttonStyle(.pill(small: true))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, Space.pageCompact)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - What's been said

/// What's been heard so far, as the desktop's transcript has it: each line's time down the side, small and subtle,
/// then the words, in ink once they've settled and subtle until then. Newest at the bottom, kept in view.
private struct LiveTranscript: View {
    var recorder: Recorder
    var inset: CGFloat = Space.pageCompact

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    let segments = recorder.recording?.segments ?? []
                    if segments.isEmpty && recorder.volatile.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What's said shows here a few seconds after it's said.")
                            Text("It's written down on this phone. Lock the phone if you like: it keeps recording.")
                        }
                        .textStyle(.summary)
                        .foregroundStyle(.inkMuted)
                    }
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                        TranscriptLine(time: Format.clock(s.start), text: s.text)
                    }
                    if !recorder.volatile.isEmpty {
                        TranscriptLine(time: Format.clock(recorder.elapsed), text: recorder.volatile, settled: false)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, inset)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .onChange(of: recorder.volatile) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: recorder.recording?.segments.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }
}

/// A line of a transcript: its time (12, medium, subtle, down the side) and its words (16 on 26).
struct TranscriptLine: View {
    var time: String
    var text: String
    var settled = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(time).font(.atkinson(12, .medium, relativeTo: .caption)).foregroundStyle(.inkSubtle)
                .frame(width: 44, alignment: .leading)
            Text(text).font(.atkinson(16, relativeTo: .body)).lineSpacing(6)
                .foregroundStyle(settled ? Color.ink : .inkSubtle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Which class

/// Which class it's for, as the desktop's breadcrumb names it: the swatch and the name in bold ink (or the inbox and
/// Unsorted), then a chevron. Tapped, the desktop's folder picker opens beside it, as a popover (never a sheet over a
/// sheet). Wherever something new is filed: a recording, an imported one, files, a GoodNotes notebook.
struct ClassPicker: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: String?
    @State private var picking = false

    var body: some View {
        let unsorted = Self.isUnsorted(selection)
        Button { picking = true } label: {
            HStack(spacing: 8) {
                if unsorted {
                    Icon("inbox", size: 15, relativeTo: .subheadline).foregroundStyle(.inkSubtle)
                    Text("Unsorted").font(.atkinson(14, .bold, relativeTo: .subheadline)).foregroundStyle(.inkMuted)
                } else {
                    Swatch(app.hue(of: selection))
                    Text(selection ?? "").font(.atkinson(14, .bold, relativeTo: .subheadline)).foregroundStyle(.ink).lineLimit(1)
                }
                Icon("expand_more", size: 14, relativeTo: .subheadline).foregroundStyle(.inkSubtle)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unsorted ? "Unsorted. Choose a \(app.words.cls)" : "In \(selection ?? ""). Change \(app.words.cls)")
        .popover(isPresented: $picking, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            ClassPickerMenu(selection: $selection) { picking = false }
                .presentationCompactAdaptation(.popover)
        }
        .task {
            #if DEBUG
            if DebugLaunch.flag("-pick-class") {
                try? await Task.sleep(for: .seconds(2))
                picking = true
            }
            #endif
        }
    }

    static func isUnsorted(_ cls: String?) -> Bool { cls == nil || cls == "Unsorted" || cls?.isEmpty == true }
}

/// The desktop's folder picker: a field that narrows the list as it's typed in, Unsorted, then each class under its
/// group's name (Classes, Clubs, Work) with its swatch and how many it holds, a check on the one chosen. A pick
/// closes it.
private struct ClassPickerMenu: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: String?
    var close: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Icon("search", size: 16).foregroundStyle(.inkSubtle)
                TextField("", text: $query, prompt: Text("Find a \(app.words.cls)").foregroundStyle(.inkSubtle))
                    .textStyle(.body)
                    .foregroundStyle(.ink)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if let first = found.first?.classes.first { pick(first.name) } }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            Rule()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if showsUnsorted { row(name: nil, count: 0) }
                    ForEach(found, id: \.group) { g in
                        GroupLabel(g.group).padding(.top, 12).padding(.bottom, 2)
                        ForEach(g.classes) { c in row(name: c.name, count: c.lectures) }
                    }
                    if found.isEmpty && !showsUnsorted {
                        Text("No \(app.words.cls) is called that.").textStyle(.summary).foregroundStyle(.inkMuted).padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.ink)
        .presentationBackground(.surface)
    }

    private var showsUnsorted: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || "unsorted".localizedCaseInsensitiveContains(q)
    }

    /// The classes that match what's typed, under their groups: Classes first, then the rest as the library has them.
    private var found: [(group: String, classes: [ClassInfo])] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matching = app.classes.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || ($0.code ?? "").localizedCaseInsensitiveContains(q) }
        var groups: [(group: String, classes: [ClassInfo])] = []
        for c in matching {
            let g = (c.group ?? "").isEmpty ? app.words.classes : c.group!
            if let i = groups.firstIndex(where: { $0.group == g }) { groups[i].classes.append(c) } else { groups.append((g, [c])) }
        }
        let first = groups.filter { $0.group == app.words.classes }
        return first + groups.filter { $0.group != app.words.classes }
    }

    private func row(name: String?, count: Int) -> some View {
        let chosen = name == nil ? ClassPicker.isUnsorted(selection) : name == selection
        let shown = name ?? "Unsorted"
        return Button { pick(name) } label: {
            HStack(spacing: 12) {
                if let name {
                    Swatch(app.hue(of: name)).frame(width: 16)
                    Text(name).textStyle(.className).fontWeight(chosen ? .bold : .regular).foregroundStyle(.ink).lineLimit(1)
                } else {
                    Icon("inbox", size: 16).foregroundStyle(.inkSubtle).frame(width: 16)
                    Text("Unsorted").textStyle(.className).fontWeight(chosen ? .bold : .regular).foregroundStyle(.ink)
                }
                Spacer(minLength: 8)
                if chosen {
                    Icon("check", size: 15).foregroundStyle(.ink)
                } else if count > 0 {
                    Text("\(count)").textStyle(.meta).foregroundStyle(.inkSubtle)
                }
            }
            .frame(minHeight: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.row)
        .accessibilityLabel(chosen ? "\(shown), chosen" : count > 0 ? "\(shown), \(count) \(count == 1 ? app.words.lecture : app.words.lectures)" : shown)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func pick(_ name: String?) {
        selection = name
        close()
    }
}

// MARK: - Record, above the tab bar

/// Above the tab bar, on every tab, the one Record: the desktop's record dot (red, a white dot in it) and "Record",
/// then the class it'll go into (`classNow`, the app's `recordClass`: this page's, else the one on the calendar now)
/// in its highlighter, or just "Record" (a recording in Unsorted). While it records: the dot breathing, the title,
/// the level and the time; a tap opens it.
struct RecordAccessory: View {
    @Environment(AppModel.self) private var app
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var recorder = Recorder.shared
    /// Where Record records (`app.recordClass`).
    var classNow: String?

    var body: some View {
        let active = recorder.isActive
        let into = classNow
        let inline = placement == .inline
        Button {
            app.record(for: active ? recorder.recording?.className : into)
        } label: {
            HStack(spacing: 10) {
                if active {
                    PulseDot(pulsing: recorder.phase == .recording)
                        .frame(width: 32, height: 32)
                    if !inline {
                        Text(recorder.recording?.displayTitle ?? "Recording").textStyle(.button).foregroundStyle(.ink).lineLimit(1)
                        Spacer(minLength: 4)
                    }
                    if recorder.phase == .recording {
                        LevelBars(levels: recorder.levels)
                    } else if recorder.phase == .paused, !inline {
                        Text("Paused").textStyle(.buttonSmall).foregroundStyle(.inkMuted)
                    }
                    Text(Format.clock(recorder.elapsed)).textStyle(.button).fontWeight(.medium).foregroundStyle(.inkMuted).fixedSize()
                } else {
                    RecordDot(state: .idle, mini: true)
                    Text("Record").textStyle(.button).foregroundStyle(.ink)
                    if let into, !inline { Highlight(into, hue: app.hue(of: into)).lineLimit(1) }
                    if !inline { Spacer(minLength: 0) }
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? "\(recorder.phase == .paused ? "Paused" : "Recording"), \(recorder.recording?.displayTitle ?? ""), \(Format.clock(recorder.elapsed))"
                            : into.map { "Record \($0)" } ?? "Record")
        .accessibilityHint(active ? "Opens the recording" : "")
    }
}

// MARK: - Stand-ins until iphone-look is merged

// FLOWS: AppModel on iphone-look has these (shared changes 3, 4 and 5); this branch can't merge it yet. Each stand-in
// does the nearest thing today's AppModel can, and each is declared so that it collides with the real one (the same
// name, or a type that's gone there): after the merge this block doesn't compile, and is deleted.
extension AppModel {
    /// FLOWS: stand-in for `recordTitle` (the title Record starts with: an event's, "Calculus II, Fri 16 Oct").
    var recordTitle: String { "" }

    /// FLOWS: stand-in for `recordClass` (where Record records: the page's class, else the one on now).
    var recordClass: String? { classNow(ResponseCache.shared.read("upcoming", as: Upcoming.self)) }

    /// FLOWS: stand-in for `go(_:tab:root:)`.
    func go(_ route: Route?, tab: MainTabs.TabID = .library, root: Bool = false) {
        incoming = nil
        showingRecorder = false
        pendingRoute = route
    }

    /// FLOWS: stand-in for `recordingFinished(id:sent:)`: the recorder closes, then the lecture (not sent: the
    /// recording on this phone, whose route comes with the merge; until then, Home, where On this phone lists it).
    func recordingFinished(id: String, sent: Bool) {
        go(sent ? .lecture(id) : nil)
    }
}
