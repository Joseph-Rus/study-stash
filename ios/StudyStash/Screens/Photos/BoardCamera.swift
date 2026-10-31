import AVFoundation
import PhotosUI
import SwiftUI

/// The camera that takes whiteboard photos for a lecture: live view, a shutter, as many shots as the student wants in
/// a row (a count says how many), Done. Each shot is kept with its lecture and its time (PhotoStore), the board found and
/// straightened. "Choose from Photos" adds ones taken with the Camera app, each tagged with its own time.
///
/// The capture session takes no audio and leaves the app's audio session alone, so a recording keeps going while
/// this is up.
struct BoardCamera: View {
    var target: PhotoTarget
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var state: CameraController.State = .starting
    @State private var count = 0
    @State private var busy = 0
    @State private var picked: [PhotosPickerItem] = []
    @State private var toast: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch state {
            case .starting, .ready:
                CameraPreview(camera: camera).ignoresSafeArea()
            case .denied:
                message("Syft Notes can't use the camera.", "Allow it in Settings to take photos of the board.", settings: true)
            case .unavailable:
                message("The camera isn't available here.", "You can still add photos from your Photos.", settings: false)
            }
        }
        .overlay(alignment: .top) { top }
        .overlay(alignment: .bottom) { bottom }
        .toast($toast)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            camera.onPhoto = { data, taken in
                Task { @MainActor in await keep(data, taken: taken, straighten: true) }
            }
            state = await camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { for item in items { await choose(item) } }
        }
    }

    private var top: some View {
        HStack {
            Text(target.label).textStyle(.meta).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 12)
            if count > 0 { Text(count == 1 ? "1 photo" : "\(count) photos").textStyle(.meta).foregroundStyle(.white) }
            Button("Done") { dismiss() }.buttonStyle(.pill(small: true, ink: true))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var bottom: some View {
        HStack {
            PhotosPicker(selection: $picked, maxSelectionCount: 20, matching: .images) {
                PhotosLabel()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { camera.capture() } label: {
                Circle().fill(.white).frame(width: 68, height: 68)
                    .overlay(Circle().strokeBorder(.black, lineWidth: 3).padding(4))
            }
            .disabled(state != .ready)
            .opacity(state == .ready ? 1 : 0.3)
            .accessibilityLabel("Take photo")
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func message(_ title: String, _ detail: String, settings: Bool) -> some View {
        VStack(spacing: 10) {
            Text(title).textStyle(.h2).foregroundStyle(.white)
            Text(detail).textStyle(.lede).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            if settings {
                Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                    .buttonStyle(.pill(small: true, ink: true)).padding(.top, 6)
            }
        }
        .padding(32)
    }

    private func keep(_ data: Data, taken: Date, straighten: Bool) async {
        if await PhotoStore.shared.add(data, for: target, taken: taken, straighten: straighten) {
            count += 1
            if let api = app.api { Task { await PhotoStore.shared.sendWaiting(api: api) } }
        } else {
            toast = "That photo couldn't be kept."
        }
    }

    /// A photo from the library keeps its own time; the Camera app's photo is already as it was taken.
    private func choose(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { toast = "That photo couldn't be read."; return }
        await keep(data, taken: WhiteboardPhoto.takenTime(of: data) ?? .now, straighten: false)
    }
}

private struct PhotosLabel: View {
    var body: some View { Label("Photos", icon: "image").textStyle(.nav).foregroundStyle(.white) }
}

/// The capture session behind the camera screen. Not main-actor bound: AVFoundation wants its own queue.
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum State { case starting, ready, denied, unavailable }

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "app.studystash.camera")
    private var rotation: AVCaptureDevice.RotationCoordinator?
    var onPhoto: (@Sendable (Data, Date) -> Void)?
    fileprivate weak var preview: AVCaptureVideoPreviewLayer?

    func start() async -> State {
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined { status = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied }
        guard status == .authorized else { return .denied }
        return await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.configure()) }
        }
    }

    private func configure() -> State {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return .unavailable }
        // The recording's audio keeps going: this session has no microphone and doesn't touch the app's audio session.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); return .unavailable }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
        return .ready
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func capture() {
        queue.async {
            let settings = self.output.availablePhotoCodecTypes.contains(.jpeg)
                ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]) : AVCapturePhotoSettings()
            if let c = self.output.connection(with: .video), let angle = self.rotation?.videoRotationAngleForHorizonLevelCapture, c.isVideoRotationAngleSupported(angle) {
                c.videoRotationAngle = angle
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        onPhoto?(data, Date())
    }

    /// Called by the preview once its layer exists: turns the picture upright for how the device is held.
    fileprivate func attach(_ layer: AVCaptureVideoPreviewLayer) {
        preview = layer
        queue.async {
            guard let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            self.rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        }
    }

    fileprivate func turn(_ layer: AVCaptureVideoPreviewLayer) {
        if let angle = rotation?.videoRotationAngleForHorizonLevelPreview, let c = layer.connection, c.isVideoRotationAngleSupported(angle) {
            c.videoRotationAngle = angle
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    var camera: CameraController

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = camera.session
        v.previewLayer.videoGravity = .resizeAspect
        v.camera = camera
        camera.attach(v.previewLayer)
        return v
    }

    func updateUIView(_ v: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var camera: CameraController?
        override func layoutSubviews() { super.layoutSubviews(); camera?.turn(previewLayer) }
    }
}
