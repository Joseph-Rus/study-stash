import SwiftUI

/// A recording on this phone that hasn't reached the library (`Route.recording(id)`): where it's got to, what was
/// typed and said, and Send now / Share the audio / Delete. A placeholder the recording lane builds out.
struct PhoneRecordingView: View {
    let id: String
    @State private var store = RecordingStore.shared

    var body: some View {
        let r = store.recordings.first { $0.id == id }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(r?.displayTitle ?? "Recording").textStyle(.docTitle).foregroundStyle(.ink)
                Text(r?.error ?? "Waiting to reach your library").textStyle(.lede).foregroundStyle(.inkMuted)
            }
            .padding(Space.pageCompact)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .page()
    }
}
