import SwiftUI

/// A recording that hasn't reached the library (`Route.recording(id)`, from Home's On this phone, or after a Stop
/// that couldn't send): its class (still the picker), when, its title, where it's got to ("Waiting to reach your
/// library", or the library's own words), then what was typed and what was said. Send now, Share the audio, Delete.
/// Once it sends, the lecture takes its place.
struct PhoneRecordingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var store = RecordingStore.shared
    @State private var sending = false
    @State private var confirmingDelete = false

    private var recording: Recording? { store.recordings.first { $0.id == id } }

    var body: some View {
        Group {
            if let r = recording {
                page(r)
            } else {
                EmptyState(title: "This recording isn't on this phone any more",
                           detail: "It was sent to your library or deleted. Anything that reached your library is on Home.")
                    .padding(.horizontal, Space.pageCompact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .page()
        .foregroundStyle(.ink)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this recording?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = recording { store.delete(r) }
                dismiss()
            }
        } message: {
            Text("It hasn't reached your library. What was said, what you typed and its audio are deleted from this phone.")
        }
    }

    private func page(_ r: Recording) -> some View {
        let date = Recording.localISO(r.started)
        let crumb = Nouns.capital(app.noun(of: r.className)) + ", " + Format.noteWhen(date, r.seconds)
        let sent = r.state == .sent
        let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ClassPicker(selection: Binding(get: { recording?.className }, set: { c in
                    guard var now = recording else { return }
                    now.className = c
                    store.save(now)
                }))
                .disabled(sent)
                Text(crumb).textStyle(.crumb).foregroundStyle(.inkMuted)
                Text(r.displayTitle).textStyle(.docTitle).foregroundStyle(.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)

                Text(status(r)).textStyle(.lede).foregroundStyle(r.state == .failed ? Color.ink : .inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                FlowLayout(spacing: 10) {
                    if sent {
                        Button { app.go(.lecture(id), root: true) } label: { Text("Open it") }
                            .buttonStyle(.pill(ink: true))
                    } else {
                        Button { Task { await send() } } label: {
                            HStack(spacing: 8) {
                                if sending { StudyLoader(.inline, color: .surface) }
                                Text(sending ? "Sending…" : "Send now")
                            }
                        }
                        .buttonStyle(.pill(ink: true))
                        .disabled(sending || app.api == nil)
                    }
                    if let audio = store.audioURL(r), FileManager.default.fileExists(atPath: audio.path) {
                        ShareLink(item: audio) { Label("Share the audio", icon: "ios_share") }
                            .buttonStyle(.pill)
                    }
                    if !sent {
                        Button { confirmingDelete = true } label: { Label("Delete", icon: "delete") }
                            .buttonStyle(.pill)
                            .disabled(sending)
                    }
                }
                .padding(.top, 20)

                if !notes.isEmpty {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(.ink).frame(width: 14, height: 3)
                        Text("What you wrote").textStyle(.legend).fontWeight(.bold).foregroundStyle(.ink)
                    }
                    .padding(.top, 32)
                    Text(notes).font(.atkinson(16, .semibold, relativeTo: .body)).lineSpacing(6).foregroundStyle(.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                SectionHeading(title: "Transcript").padding(.top, 28)
                if r.segments.isEmpty {
                    EmptyText("Nothing was heard in this \(app.noun(of: r.className)).").padding(.top, 8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(r.segments.enumerated()), id: \.offset) { _, s in
                            TranscriptLine(time: Format.clock(s.start), text: s.text)
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, Space.pageCompact)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// Where it's got to, in plain words.
    private func status(_ r: Recording) -> String {
        switch r.state {
        case .sent: "It's in your library now."
        case .sending: "Sending it to your library…"
        case .failed: r.error ?? "Your library couldn't take it."
        default: r.error ?? (app.isDrive ? "On its way to your laptop. Its notes are written when your laptop is on."
                             : app.offline || app.api == nil ? "Waiting to reach your library. It's sent on its own once your phone can reach your computer."
                             : "Waiting to reach your library.")
        }
    }

    private func send() async {
        guard let api = app.api else { return }
        sending = true
        await store.send(id, api: api)
        sending = false
        if recording?.state == .sent { app.go(.lecture(id), root: true) }
    }
}
