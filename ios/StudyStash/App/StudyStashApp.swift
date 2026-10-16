import CoreSpotlight
import SwiftUI
import UserNotifications

@main
struct StudyStashApp: App {
    @State private var app = AppModel()
    @AppStorage("theme") private var themeName = ColourTheme.lagoon.name

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(ColourTheme.named(themeName).accent)
                .task { NotificationRouter.shared.app = app }
        }
        .backgroundTask(.appRefresh(Reminders.refreshTask)) {
            await app.refreshInBackground()
            await Reminders.scheduleRefresh()
        }
    }
}

/// Where a tap goes inside a tab.
enum Route: Hashable {
    case classDetail(String)
    case lecture(String)
    case assignment(class: String, id: Int)
    case search(String)
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch app.phase {
            case .unpaired:
                PairView().transition(.opacity)
            case .checking, .ready:
                MainTabs().id(app.api?.base).transition(.opacity)
            }
        }
        .animation(.smooth, value: app.phase)
        .task {
            #if DEBUG
            await DebugLaunch.pairIfAsked(app)
            #endif
            if app.phase == .checking { await app.check() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, app.phase != .unpaired, DebugLaunch.value("-library") == nil { Task { await app.check() } }
            if phase == .background { Reminders.scheduleRefresh() }
        }
    }
}

struct MainTabs: View {
    enum TabID: Hashable { case library, due, ask, settings, search }
    @Environment(AppModel.self) private var app
    @State private var tab: TabID = DebugLaunch.tab ?? .library
    @State private var upcoming: Upcoming? = ResponseCache.shared.read("upcoming", as: Upcoming.self)

    var body: some View {
        TabView(selection: $tab) {
            Tab("Library", systemImage: "books.vertical", value: .library) { LibraryTab() }
            if app.forSchool { Tab("Due", systemImage: "checklist", value: .due) { DueTab() } }
            Tab("Ask", systemImage: "sparkles", value: .ask) { AskTab() }
            Tab("Settings", systemImage: "gearshape", value: .settings) { SettingsTab() }
            Tab(value: .search, role: .search) { SearchTab() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { RecordAccessory(classNow: app.classNow(upcoming)) }
        .sheet(isPresented: Binding(get: { (app.needsUses || DebugLaunch.value("-uses") != nil) && app.phase == .ready && !app.askedUses }, set: { if !$0 { app.askedUses = true } })) {
            UsesView(onboarding: true)
        }
        .sheet(isPresented: Binding(get: { app.showingRecorder }, set: { app.showingRecorder = $0 })) {
            RecordView(startClass: app.recordFor)
        }
        .sheet(item: Binding(get: { app.incoming }, set: { app.incoming = $0 })) { incoming in
            switch incoming {
            case let .files(files, cls, lecture): AddFilesView(className: cls, lecture: lecture, files: files)
            case .audio(let file): ImportAudioView(file: file)
            case .goodnotes(let url): GoodNotesImportView(url: url)
            case let .handwriting(cls, lecture): HandwritingView(className: cls, lecture: lecture).interactiveDismissDisabled()
            }
        }
        .onOpenURL { app.open($0) }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String { app.pendingRoute = .lecture(id) }
        }
        .onChange(of: app.pendingRoute) { _, r in if r != nil { tab = .library } }
        .task {
            // Pause, Stop and Record from the lock screen, Control Center and Siri.
            RecordingControl.stop = { [app] in await Recorder.shared.stop(api: app.api) }
            RecordingControl.togglePause = { Recorder.shared.phase == .paused ? Recorder.shared.resume() : Recorder.shared.pause() }
            RecordingControl.start = { [app] in app.record(for: app.classNow(ResponseCache.shared.read("upcoming", as: Upcoming.self))) }
            // Notifications are asked for after "What's it for?", not on top of it.
            if !app.needsUses && DebugLaunch.value("-uses") == nil { Task { await Reminders.setUp() } }
            upcoming = try? await app.api?.upcoming()
            await app.refreshInBackground()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-record") { app.record(for: app.classNow(upcoming)) }
            if let path = DebugLaunch.value("-open-file") { app.open(URL(fileURLWithPath: path)) }
            if let dir = DebugLaunch.value("-export-notebooks") {
                for n in NotebookStore.shared.notebooks {
                    try? NotebookStore.shared.pdfData(n).write(to: URL(fileURLWithPath: dir).appending(path: "\(n.title).pdf"))
                }
            }
            #endif
        }
    }
}

/// The destinations every tab's stack can push.
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case .classDetail(let name): ClassView(name: name)
            case .lecture(let id): LectureView(id: id)
            case let .assignment(cls, id): AssignmentView(className: cls, id: id)
            case .search(let q): SearchResultsView(query: q)
            }
        }
    }
}

extension View {
    func routes() -> some View { modifier(RouteDestinations()) }
}

/// Launch arguments for screenshots and testing in the simulator, where there's no camera to scan with:
/// `-pair <address> <code>` pairs on launch, `-library <address>` uses a library with no password, `-tab due|ask|settings|search` opens a tab, `-open lecture:<id>` or
/// `-open class:<name>` pushes a screen onto the Library tab.
enum DebugLaunch {
    static func value(_ flag: String, _ offset: Int = 1) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + offset) else { return nil }
        return args[i + offset]
        #else
        return nil
        #endif
    }

    static var tab: MainTabs.TabID? {
        switch value("-tab") {
        case "due": .due
        case "ask": .ask
        case "settings": .settings
        case "search": .search
        default: nil
        }
    }

    static var route: Route? {
        guard let v = value("-open") else { return nil }
        if v.hasPrefix("lecture:") { return .lecture(String(v.dropFirst(8))) }
        if v.hasPrefix("class:") { return .classDetail(String(v.dropFirst(6))) }
        return nil
    }

    @MainActor static func pairIfAsked(_ app: AppModel) async {
        // `-library <address>`: use a library with no password (a test one) without pairing.
        if let address = value("-library"), let base = LibraryAddress.candidates(from: address).first,
           let me = try? await APIClient(base: base, session: AppModel.session).me() {
            app.paired(base: base, library: me.library)
            return
        }
        guard let address = value("-pair"), let code = value("-pair", 2) else { return }
        for base in LibraryAddress.candidates(from: address) {
            let api = APIClient(base: base, session: AppModel.session)
            guard let me = try? await api.me() else { continue }
            if (try? await api.pair(code: code, name: "Simulator")) != nil { app.paired(base: base, library: me.library) }
            return
        }
    }
}
