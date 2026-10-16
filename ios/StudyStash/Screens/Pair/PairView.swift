import SwiftUI
import UIKit
import VisionKit

/// Adding this phone to a library: find it (scan the QR code in Study Stash's Settings → Phone → Add a phone, or
/// paste its address), then type the 6-digit code shown beside it.
struct PairView: View {
    @Environment(AppModel.self) private var app

    enum Step: Equatable { case welcome, finding, code(base: URL, library: Me.Library) }

    @State private var step: Step = .welcome
    @State private var address = ""
    @State private var scanning = false
    @State private var typing = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop
                switch step {
                case .welcome, .finding:
                    welcome
                case let .code(base, library):
                    CodeEntry(base: base, library: library) { step = .welcome }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: step)
            .sheet(isPresented: $scanning) {
                QRScanner { text in
                    scanning = false
                    Task { await find(text) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var backdrop: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.22), .paper, .paper], startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(Color.accentColor.gradient)
                .padding(26)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.15)), in: .rect(cornerRadius: 30))
                .padding(.bottom, 28)
            Text("Study Stash")
                .font(.display)
            Text("Every lecture, written up — in your pocket.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                step(1, "On your computer, open Study Stash → Settings → Phone → **Add a phone**.")
                step(2, "Scan the QR code it shows, then type the 6-digit code.")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .padding(.bottom, 20)

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }

            VStack(spacing: 10) {
                Button {
                    problem = nil
                    if DataScannerViewController.isSupported { scanning = true } else { typing = true }
                } label: {
                    Label(step == .finding ? "Finding your library…" : "Scan the QR code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(step == .finding)

                Button("Type the address instead") { typing = true }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .alert("Your library's address", isPresented: $typing) {
            TextField("mac.tail1234.ts.net:8443", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Cancel", role: .cancel) {}
            Button("Find") { Task { await find(address) } }
        } message: {
            Text("It's under the QR code in Study Stash's Settings → Phone → Add a phone.")
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.gradient, in: .circle)
            Text(text).font(.callout)
        }
    }

    /// Try each address the scan or paste gave, best first, until one is a library.
    private func find(_ text: String) async {
        let candidates = LibraryAddress.candidates(from: text)
        guard !candidates.isEmpty else {
            problem = "That isn't a Study Stash address. Scan the QR code in Settings → Phone → Add a phone."
            return
        }
        step = .finding
        problem = nil
        for base in candidates {
            if let me = try? await APIClient(base: base, session: AppModel.session).me() {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                step = .code(base: base, library: me.library)
                return
            }
        }
        step = .welcome
        problem = "Couldn't reach a library there. Turn Tailscale on here and on your computer, keep Study Stash open, and try again."
    }
}

/// The six digits, in big boxes, sent as soon as the sixth is typed.
private struct CodeEntry: View {
    @Environment(AppModel.self) private var app
    var base: URL
    var library: Me.Library
    var back: () -> Void

    @State private var code = ""
    @State private var name = UIDevice.current.name
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce, value: library.name)
            VStack(spacing: 6) {
                Text("Found \(library.name)").font(.titleSerif).multilineTextAlignment(.center)
                Text("Type the 6-digit code Study Stash shows beside the QR code.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            ZStack {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.02)
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(6))
                        if digits != new { code = digits }
                        if digits.count == 6 { Task { await pair() } }
                    }
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        let chars = Array(code)
                        Text(i < chars.count ? String(chars[i]) : "")
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 46, height: 58)
                            .background(.card, in: .rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(i == chars.count && focused ? Color.accentColor : .secondary.opacity(0.2), lineWidth: i == chars.count && focused ? 2 : 1)
                            }
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(.rect)
            .onTapGesture { focused = true }
            .modifier(Shake(times: problem == nil ? 0 : 1))

            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What should we call this phone?").font(.footnote).foregroundStyle(.secondary)
                TextField("iPhone", text: $name)
                    .padding(12)
                    .background(.card, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .padding(.top, 8)

            Spacer()
            Button {
                Task { await pair() }
            } label: {
                Group { if busy { ProgressView() } else { Text("Pair") } }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(code.count != 6 || busy)
            Button("Use a different library", action: back).font(.subheadline)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 520)
        .onAppear { focused = true }
    }

    private func pair() async {
        guard code.count == 6, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let api = APIClient(base: base, session: AppModel.session)
            _ = try await api.pair(code: code, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? UIDevice.current.name : name)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.smooth) { app.paired(base: base, library: library) }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.default) { problem = (error as? APIError)?.detail ?? "Couldn't reach your library. Try again." }
            code = ""
        }
    }
}

/// A side-to-side shake, for a wrong code.
struct Shake: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(times * .pi * 4), y: 0))
    }
}

/// The camera, reading the first QR code it sees.
struct QRScanner: UIViewControllerRepresentable {
    var found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        var done = false
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(code) in items {
                guard !done, let text = code.payloadStringValue else { continue }
                done = true
                scanner.stopScanning()
                found(text)
            }
        }
    }
}
