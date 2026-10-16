@preconcurrency import AVFoundation
import Speech
import SwiftUI

/// A recording made elsewhere (Voice Memos, a file) becomes a lecture: written down on this phone, then sent like
/// one recorded here. A phone that can't write speech down sends the audio, for a computer that records to do it.
/// In the look of the Attach sheet's rows: the file, its class (the class picker: where it was opened from, else the
/// class on the calendar now) and its title; while it's written down, how far it's got. Once sent, it goes where Stop
/// goes: the lecture, or the recording on this phone.
struct ImportAudioView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var file: PendingFile?
    @State var className: String?

    @State private var title = ""
    @State private var picking = false
    @State private var progress: Double?
    @State private var result: String?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    sentToComputer(result)
                } else {
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .page()
            .foregroundStyle(.ink)
            .navigationTitle(result == nil ? "Import a recording" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(result == nil ? "Cancel" : "Done").textStyle(.nav) }
                        .disabled(progress != nil)
                }
                if result == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await run() } } label: { Text("Import").textStyle(.button) }
                            .disabled(file == nil || progress != nil)
                    }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .mpeg4Audio, .movie]) { r in
                if case .success(let url) = r { file = PendingFile.from(url: url) }
            }
        }
        .interactiveDismissDisabled(progress != nil)
        .onAppear {
            // Opened with no class: the one on the calendar now, as Record has it.
            if className == nil {
                className = app.recordHere ?? app.classNow(ResponseCache.shared.read("upcoming", as: Upcoming.self))
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The recording: its name and size; tapped, choose another.
                Button { picking = true } label: {
                    row(icon: "graphic_eq") {
                        Text(file?.name ?? "Choose a recording").textStyle(.nav).foregroundStyle(.ink)
                            .multilineTextAlignment(.leading)
                        Text(file.map { "\(Format.fileSize($0.data.count)). Tap to choose another." } ?? "From Voice Memos or Files")
                            .textStyle(.meta).foregroundStyle(.inkMuted)
                    }
                }
                .buttonStyle(.row)
                .disabled(progress != nil)
                .accessibilityHint("Choose the recording to import")
                Rule()

                // Its class.
                row(icon: "folder") {
                    Text(Nouns.capital(app.words.cls)).textStyle(.nav).foregroundStyle(.ink)
                    ClassPicker(selection: $className).padding(.vertical, -6)
                }
                .disabled(progress != nil)
                Rule()

                // Its title.
                row(icon: "edit") {
                    Text("Title").textStyle(.nav).foregroundStyle(.ink)
                    TextField("", text: $title, prompt: Text("Named from what's said").foregroundStyle(.inkSubtle))
                        .textStyle(.body)
                        .foregroundStyle(.ink)
                        .submitLabel(.done)
                }
                .disabled(progress != nil)
                Rule()

                Text("It's written down on this phone, then sent to \(app.libraryName), where its notes are written. From Voice Memos: tap ••• on a recording, then Share, then Study Stash.")
                    .textStyle(.meta)
                    .foregroundStyle(.inkSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                if let progress {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Writing down what's said…").textStyle(.body).foregroundStyle(.ink)
                            Spacer()
                            Text("\(Int((progress * 100).rounded()))%").textStyle(.meta).foregroundStyle(.inkSubtle)
                        }
                        ProgressView(value: progress).tint(.ink)
                    }
                    .padding(.top, 24)
                    .accessibilityElement(children: .combine)
                }
                if let problem {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Icon("warning", size: 16).foregroundStyle(.ink)
                        Text(problem).textStyle(.body).foregroundStyle(.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, Space.pageCompact)
            .padding(.top, 8)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// One of the sheet's rows: an icon, then its words, one under the other.
    private func row<Words: View>(icon: String, @ViewBuilder _ words: () -> Words) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Icon(icon, size: 20).foregroundStyle(.inkMuted).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 3) { words() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    /// Sent as audio, for a computer that records to write down (this phone can't).
    private func sentToComputer(_ words: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sent to \(app.libraryName)").textStyle(.docTitle).foregroundStyle(.ink).padding(.top, 12)
            EmptyText(words)
            Button { dismiss() } label: { Text("Done") }
                .buttonStyle(.pill(ink: true))
                .padding(.top, 16)
        }
        .padding(.horizontal, Space.pageCompact)
    }

    private func run() async {
        guard let file, let api = app.api else { return }
        problem = nil
        progress = 0
        defer { progress = nil }
        let temp = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(file.name)")
        try? file.data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            let (segments, seconds, language) = try await AudioFileTranscriber.transcribe(temp) { p in
                Task { @MainActor in progress = p }
            }
            var r = Recording(id: Recording.newID(), started: (try? temp.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now,
                              className: className, title: title, titleTyped: !title.isEmpty)
            r.segments = segments
            r.seconds = seconds
            r.language = language
            r.state = .waiting
            RecordingStore.shared.save(r)
            await RecordingStore.shared.send(r.id, api: api)
            // Where Stop goes: the lecture, or the recording on this phone.
            app.recordingFinished(id: r.id, sent: RecordingStore.shared.recordings.first { $0.id == r.id }?.state == .sent)
        } catch let e as RecorderError where e.words.hasPrefix("This phone can't") {
            // No speech model here: a computer that records writes it down instead.
            do {
                _ = try await api.sendVoiceMemo(name: file.name, data: file.data, type: file.type, class: className, title: title.isEmpty ? nil : title)
                result = "A computer that records writes down what's said, then its notes are written. It'll be on Home once they are."
            } catch {
                problem = (error as? APIError)?.detail ?? "Couldn't send it."
            }
        } catch {
            problem = (error as? RecorderError)?.words ?? "Couldn't read that recording: \(error.localizedDescription)"
        }
    }
}

/// Writes down a whole audio file on this phone.
enum AudioFileTranscriber {
    static func transcribe(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> ([Recording.Segment], Double, String) {
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        let (module, results, locale) = try await Recorder.transcriber()
        let analyzer = SpeechAnalyzer(modules: [module])
        let reading = Task {
            var segments: [Recording.Segment] = []
            for try await r in results where r.isFinal {
                let text = r.text.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                if let last = segments.last, r.start - last.start < 8, last.text.count < 160 {
                    segments[segments.count - 1].text += " " + text
                } else {
                    segments.append(.init(start: r.start, text: text))
                }
                if seconds > 0 { progress(min(1, r.start / seconds)) }
            }
            return segments
        }
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        let segments = try await reading.value
        progress(1)
        return (segments, seconds, locale.identifier)
    }
}
