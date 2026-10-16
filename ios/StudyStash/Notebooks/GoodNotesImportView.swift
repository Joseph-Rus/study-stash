import SwiftUI

/// A GoodNotes notebook (shared from GoodNotes: Share → Export → GoodNotes format) brought in as a notebook here:
/// every page, its PDF and its ink, which stays ink (keep writing on it), then saved to the library for notes and Ask.
struct GoodNotesImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let url: URL

    @State private var book: GoodNotesNotebook?
    @State private var problem: String?
    @State private var className: String?
    @State private var working = false
    @State private var opened: UUID?

    var body: some View {
        if let opened {
            NotebookEditor(id: opened)
        } else {
            NavigationStack {
                Form {
                    if let book {
                        Section {
                            LabeledContent("Notebook", value: book.title)
                            LabeledContent("Pages", value: "\(book.pages.count)")
                            LabeledContent("Strokes", value: "\(book.pages.reduce(0) { $0 + $1.strokes.count })")
                        } footer: {
                            Text("Your ink comes in as ink: keep writing on it here. Saved to your library, it's read for notes and Ask.")
                        }
                        Section("Class") { ClassPicker(selection: $className) }
                    } else if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else {
                        ProgressView("Reading the notebook…")
                    }
                }
                .navigationTitle("From GoodNotes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await bringIn() } } label: { if working { ProgressView() } else { Text("Import").bold() } }
                            .disabled(book == nil || working)
                    }
                }
            }
            .task {
                await read()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-import-local"), let book {
                    opened = NotebookStore.shared.importGoodNotes(book, className: nil, lecture: nil).id
                }
                #endif
            }
        }
    }

    private func read() async {
        let url = url
        let title = url.deletingPathExtension().lastPathComponent
        do {
            let book = try await Task.detached(priority: .userInitiated) { () throws -> GoodNotesNotebook in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try GoodNotesNotebook(data: Data(contentsOf: url), title: title)
            }.value
            self.book = book
        } catch {
            problem = (error as? GoodNotesError)?.words ?? "That isn't a GoodNotes notebook Study Stash can read. In GoodNotes, try Share → Export → PDF instead."
        }
    }

    private func bringIn() async {
        guard let book else { return }
        working = true
        defer { working = false }
        let n = NotebookStore.shared.importGoodNotes(book, className: className, lecture: nil)
        if let api = app.api { try? await NotebookStore.shared.upload(n.id, api: api) }
        opened = n.id
    }
}
