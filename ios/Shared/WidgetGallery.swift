import SwiftUI

/// Every widget, the Lock Screen's and the Live Activity's views at their real sizes, in one screen the app can show
/// (debug builds: launch with `-demo -show widgets`), so they can be pictured in the simulator, which can't put a
/// widget on its Home Screen headless. Compiled into the app and the widget extension both. The widgets lane fills it.
struct WidgetGallery: View {
    var body: some View {
        Text("No widgets here yet.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
