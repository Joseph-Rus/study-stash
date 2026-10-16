import SwiftUI

/// Recording a lecture: what's said appearing as it's said, a page to type notes on, and the controls in glass at
/// the bottom. The class is the one on the calendar now, or picked here.
struct RecordView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = Recorder.shared
    var startClass: String?

    enum Pane: String, CaseIterable { case transcript = "Transcript", notes = "My notes" }
    @State private var pane: Pane = .transcript
    @State private var confirmingDiscard = false
    @State private var sent: Recording?
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.paper.ignoresSafeArea()
                if let sent {
                    SentView(recording: sent) { dismiss() }
                } else {
                    content
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hide", systemImage: "chevron.down") { dismiss() }
                }
                if recorder.isActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Discard recording", systemImage: "trash", role: .destructive) { confirmingDiscard = true }
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
            }
            .confirmationDialog("Discard this recording?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { recorder.discard(); dismiss() }
            } message: {
                Text("What was said and what you typed are deleted from this phone.")
            }
        }
        .interactiveDismissDisabled(recorder.phase == .finishing)
        .task {
            if recorder.phase == .idle || isFailed {
                await recorder.start(className: startClass)
            }
            #if DEBUG
            if let after = DebugLaunch.value("-stop-after").flatMap(Double.init) {
                try? await Task.sleep(for: .seconds(after))
                let id = recorder.recording?.id
                await recorder.stop(api: app.api)
                sent = RecordingStore.shared.recordings.first { $0.id == id }
            }
            #endif
        }
    }

    private var isFailed: Bool { if case .failed = recorder.phase { true } else { false } }

    @ViewBuilder private var content: some View {
        switch recorder.phase {
        case .preparing(let words):
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(words).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
        case .failed(let words):
            ContentUnavailableView {
                Label("Can't record", systemImage: "mic.slash")
            } description: {
                Text(words)
            } actions: {
                Button("Try again") { Task { await recorder.start(className: startClass) } }.buttonStyle(.borderedProminent)
            }
        default:
            recordingBody
        }
    }

    private var recordingBody: some View {
        VStack(spacing: 0) {
            header
            Picker("Show", selection: $pane.animation(.snappy)) {
                ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            switch pane {
            case .transcript: LiveTranscript(recorder: recorder)
            case .notes: notesEditor
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
    }

    private var header: some View {
        let r = recorder.recording
        return VStack(alignment: .leading, spacing: 8) {
            ClassPicker(selection: Binding(get: { r?.className }, set: { c in recorder.update { $0.className = c } }))
            TextField("Add a title", text: Binding(
                get: { r?.title ?? "" },
                set: { t in recorder.update { $0.title = t; $0.titleTyped = !t.isEmpty } }), axis: .vertical)
                .font(.titleSerif)
                .lineLimit(1...3)
                .submitLabel(.done)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesEditor: some View {
        TextEditor(text: Binding(get: { recorder.recording?.notes ?? "" }, set: { n in recorder.update { $0.notes = n } }))
            .focused($typing)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 16)
            .overlay(alignment: .topLeading) {
                if (recorder.recording?.notes ?? "").isEmpty {
                    Text("Type what matters as you hear it. Your notes are kept as you wrote them, and the lecture's notes are written around them.")
                        .font(.body).foregroundStyle(.tertiary)
                        .padding(.horizontal, 21).padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { typing = true }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                recorder.phase == .paused ? recorder.resume() : recorder.pause()
            } label: {
                Image(systemName: recorder.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(recorder.phase == .finishing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(recorder.phase == .recording ? .red : .orange).frame(width: 8, height: 8)
                        .opacity(recorder.phase == .recording ? 1 : 0.6)
                    Text(Format.clock(recorder.elapsed)).font(.title3.monospacedDigit().weight(.semibold))
                    if recorder.phase == .paused { Text("Paused").font(.caption.weight(.medium)).foregroundStyle(.orange) }
                    if recorder.phase == .finishing { Text("Saving…").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                }
                Waveform(levels: recorder.levels, active: recorder.phase == .recording)
                    .frame(height: 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    let id = recorder.recording?.id
                    await recorder.stop(api: app.api)
                    sent = RecordingStore.shared.recordings.first { $0.id == id }
                }
            } label: {
                Group {
                    if recorder.phase == .finishing { ProgressView().tint(.white) } else { Image(systemName: "stop.fill").font(.title3) }
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(.red)
            .disabled(recorder.phase == .finishing)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

/// What's been said, newest at the bottom, the words not settled yet in grey.
private struct LiveTranscript: View {
    var recorder: Recorder

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    let segments = recorder.recording?.segments ?? []
                    if segments.isEmpty && recorder.volatile.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "waveform").font(.title).foregroundStyle(.tint).symbolEffect(.variableColor.iterative)
                            Text("Listening…").font(.headline)
                            Text("What's said is written down here, on this phone, as it's said. Lock the phone if you like: it keeps going.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.top, 30)
                    }
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(Format.clock(s.start)).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.tint)
                                .frame(width: 44, alignment: .trailing)
                            Text(s.text).font(.body).textSelection(.enabled)
                        }
                    }
                    if !recorder.volatile.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(Format.clock(recorder.elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                .frame(width: 44, alignment: .trailing)
                            Text(recorder.volatile).font(.body).foregroundStyle(.secondary)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .onChange(of: recorder.volatile) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: recorder.recording?.segments.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }
}

/// The last few seconds' loudness, as bars.
struct Waveform: View {
    var levels: [Float]
    var active: Bool

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, l in
                    Capsule()
                        .fill(active ? Color.red.opacity(0.75) : Color.secondary.opacity(0.4))
                        .frame(height: max(3, CGFloat(l) * geo.size.height))
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.linear(duration: 0.1), value: levels)
        }
    }
}

/// Which class it's for: the classes as chips in a menu, or none (the library sorts it).
struct ClassPicker: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: String?

    var body: some View {
        Menu {
            Button { selection = nil } label: { Label("Let Study Stash sort it", systemImage: "wand.and.stars") }
            Divider()
            ForEach(app.classes) { c in
                Button { selection = c.name } label: {
                    if selection == c.name { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                ClassDot(color: selection.map { app.color(of: $0) } ?? .secondary, size: 8)
                Text(selection ?? "Any class").font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(selection.map { app.color(of: $0) } ?? .secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((selection.map { app.color(of: $0) } ?? .secondary).opacity(0.12), in: .capsule)
        }
    }
}

/// After Stop: sent (its notes are being written), or kept here to send when the library can be reached.
private struct SentView: View {
    @Environment(AppModel.self) private var app
    var recording: Recording
    var done: () -> Void

    var body: some View {
        let ok = recording.state == .sent
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "tray.and.arrow.up.fill")
                .font(.system(size: 56))
                .foregroundStyle(ok ? Color.green.gradient : Color.orange.gradient)
                .symbolEffect(.bounce, value: ok)
            Text(ok ? "Sent to \(app.libraryName)" : "Saved on this phone").font(.titleSerif)
            Text(ok ? "Notes are being written now. They'll be in your library in a minute or two."
                 : (recording.error ?? "It's sent as soon as your library can be reached."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("\(recording.displayTitle) · \(Format.duration(recording.seconds))")
                .font(.footnote).foregroundStyle(.tertiary)
            Spacer()
            Button(action: done) { Text("Done").frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(24)
    }
}

/// Above the tab bar: Record (for the class on the calendar now), or, while recording, the time and how loud, a
/// tap from the recording.
struct RecordAccessory: View {
    @Environment(AppModel.self) private var app
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var recorder = Recorder.shared
    var classNow: String?

    var body: some View {
        Button {
            app.record(for: recorder.isActive ? recorder.recording?.className : classNow)
        } label: {
            HStack(spacing: 10) {
                if recorder.isActive {
                    Circle().fill(.red).frame(width: 9, height: 9)
                        .symbolEffect(.pulse, isActive: recorder.phase == .recording)
                    Text(Format.clock(recorder.elapsed)).font(.subheadline.monospacedDigit().weight(.semibold))
                    if placement != .inline {
                        Text(recorder.recording?.displayTitle ?? "Recording").font(.subheadline).lineLimit(1).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Waveform(levels: Array(recorder.levels.suffix(16)), active: recorder.phase == .recording).frame(width: 52, height: 16)
                    }
                } else {
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                    Text(classNow.map { "Record \($0)" } ?? "Record a lecture").font(.subheadline.weight(.semibold)).lineLimit(1)
                    if placement != .inline { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
