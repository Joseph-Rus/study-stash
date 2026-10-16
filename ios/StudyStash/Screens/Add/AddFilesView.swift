import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// A file on its way to the library: its name, type and bytes.
struct PendingFile: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var type: String
    var data: Data

    var isImage: Bool { type.hasPrefix("image/") }

    static func from(url: URL) -> PendingFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return PendingFile(name: url.lastPathComponent, type: type, data: data)
    }
}

/// Adding files to a class (and a lecture): photos of handwritten notes, scanned pages, slides, PDFs. The library
/// reads them (handwriting too), and its notes and Ask use them.
struct AddFilesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State var className: String?
    var lecture: (id: String, title: String)?
    @State var files: [PendingFile] = []

    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var scanning = false
    @State private var sending = false
    @State private var problem: String?
    @State private var done: [Attachment]?

    var body: some View {
        NavigationStack {
            Form {
                if let done {
                    Section {
                        Label("Added \(done.count) file\(done.count == 1 ? "" : "s") to \(lecture?.title ?? className ?? "your library")",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Study Stash reads them on your computer, handwriting too. Notes and Ask use what's in them.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    if lecture == nil {
                        Section(app.words.cls.capitalized) { ClassPicker(selection: $className) }
                    } else if let lecture {
                        Section("Lecture") { Text(lecture.title) }
                    }
                    Section {
                        Button { scanning = true } label: { Label("Scan pages", systemImage: "doc.viewfinder") }
                            .disabled(!VNDocumentCameraViewController.isSupported)
                        PhotosPicker(selection: $photos, maxSelectionCount: 30, matching: .images) {
                            Label("Choose photos", systemImage: "photo.on.rectangle")
                        }
                        Button { importing = true } label: { Label("Choose files", systemImage: "folder") }
                    } footer: {
                        Text("Photos of handwritten notes, slides, PDFs, worksheets. Up to 200 MB at a time.")
                    }
                    if !files.isEmpty {
                        Section("To add") {
                            ForEach(files) { f in
                                HStack(spacing: 12) {
                                    Thumbnail(file: f)
                                    VStack(alignment: .leading) {
                                        Text(f.name).lineLimit(1)
                                        Text(Format.fileSize(f.data.count)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete { files.remove(atOffsets: $0) }
                        }
                    }
                    if let problem {
                        Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                }
            }
            .navigationTitle("Add files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(done == nil ? "Cancel" : "Done") { dismiss() } }
                if done == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await send() } } label: {
                            if sending { ProgressView() } else { Text("Add").bold() }
                        }
                        .disabled(files.isEmpty || sending)
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .presentation, .text, .item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { files += urls.compactMap(PendingFile.from(url:)) }
            }
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { pdf in
                    if let pdf { files.append(PendingFile(name: "Scan \(Date.now.formatted(date: .abbreviated, time: .shortened)).pdf", type: "application/pdf", data: pdf)) }
                    scanning = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: photos) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let type = item.supportedContentTypes.first ?? .jpeg
                            let ext = type.preferredFilenameExtension ?? "jpg"
                            files.append(PendingFile(name: "Photo \(files.count + 1).\(ext)", type: type.preferredMIMEType ?? "image/jpeg", data: data))
                        }
                    }
                    photos = []
                }
            }
        }
    }

    private func send() async {
        guard let api = app.api, !files.isEmpty else { return }
        sending = true
        problem = nil
        defer { sending = false }
        do {
            let added = try await api.upload(files: files.map { ($0.name, $0.type, $0.data) }, class: className, lecture: lecture?.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { done = added }
        } catch {
            problem = (error as? APIError)?.detail ?? "Couldn't add those. Try again."
        }
    }
}

private struct Thumbnail: View {
    var file: PendingFile
    var body: some View {
        Group {
            if file.isImage, let image = UIImage(data: file.data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: file.type.contains("pdf") ? "doc.richtext" : "doc").font(.title3).foregroundStyle(.tint)
            }
        }
        .frame(width: 40, height: 40)
        .background(.tint.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8, style: .continuous))
    }
}

/// The camera's document scanner: pages straightened and cropped, handed back as one PDF.
struct DocumentScanner: UIViewControllerRepresentable {
    var done: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let data = NSMutableData()
            let first = scan.imageOfPage(at: 0)
            UIGraphicsBeginPDFContextToData(data, CGRect(origin: .zero, size: first.size), nil)
            for i in 0..<scan.pageCount {
                let page = scan.imageOfPage(at: i)
                UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: page.size), nil)
                page.draw(at: .zero)
            }
            UIGraphicsEndPDFContext()
            done(data as Data)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done(nil) }
    }
}
