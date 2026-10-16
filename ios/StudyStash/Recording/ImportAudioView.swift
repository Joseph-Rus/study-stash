@preconcurrency import AVFoundation
import Speech
import SwiftUI

/// A recording made elsewhere (Voice Memos, a file) becomes a lecture: written down on this phone, then sent like
/// one recorded here. A phone that can't write speech down sends the audio, for a computer that records to do it.
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
            Form {
                if let result {
                    Section {
                        Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                } else {
                    Section {
                        if let file {
                            LabeledContent(file.name, value: Format.fileSize(file.data.count))
                        }
                        Button(file == nil ? "Choose a recording" : "Choose another") { picking = true }
                    } footer: {
                        Text("In Voice Memos, tap ••• → Share → Study Stash, or choose the file here.")
                    }
                    Section("Class") { ClassPicker(selection: $className) }
                    Section("Title") { TextField("Named from what's said", text: $title) }
                    if let progress {
                        Section {
                            ProgressView(value: progress) { Text("Writing down what's said…") }
                        }
                    }
                    if let problem {
                        Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                }
            }
            .navigationTitle("Import a recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Cancel" : "Done") { dismiss() } }
                if result == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") { Task { await run() } }.bold().disabled(file == nil || progress != nil)
                    }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .mpeg4Audio, .movie]) { r in
                if case .success(let url) = r { file = PendingFile.from(url: url) }
            }
        }
        .interactiveDismissDisabled(progress != nil)
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
            let now = RecordingStore.shared.recordings.first { $0.id == r.id }
            result = now?.state == .sent ? "Sent to \(app.libraryName). Notes are being written now." : (now?.error ?? "Saved on this phone; it's sent when your library can be reached.")
        } catch let e as RecorderError where e.words.hasPrefix("This phone can't") {
            // No speech model here: a computer that records writes it down instead.
            do {
                _ = try await api.sendVoiceMemo(name: file.name, data: file.data, type: file.type, class: className, title: title.isEmpty ? nil : title)
                result = "Sent to \(app.libraryName). A computer that records writes it down, then its notes are written."
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
