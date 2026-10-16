import CoreSpotlight
import SwiftUI
import UserNotifications

@main
struct StudyStashApp: App {
    @State private var app = AppModel()
    /// Light, dark, or as the phone is (Settings' choice).
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        SystemLook.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                // The desktop's look: no accent (the tint is ink), one typeface, the page's white behind.
                .tint(.ink)
                .font(.app(.body))
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
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
    #if DEBUG
    @State private var debugSheet: DebugScreen?
    @State private var debugCover: DebugScreen?
    #endif

    var body: some View {
        TabView(selection: $tab) {
            // The desktop's names and icons: Home and Due as its sidebar has them.
            Tab("Home", image: "home", value: .library) { LibraryTab() }
            if app.forSchool { Tab("Due", image: "event_upcoming", value: .due) { DueTab() } }
            Tab("Ask", image: "chat", value: .ask) { AskTab() }
            Tab("Settings", image: "settings", value: .settings) { SettingsTab() }
            Tab("Search", image: "search", value: .search, role: .search) { SearchTab() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { RecordAccessory(classNow: app.classNow(upcoming)) }
        .sheet(isPresented: Binding(get: { (app.needsUses || DebugLaunch.flag("-uses") || DebugLaunch.value("-show") == "uses") && app.phase == .ready && !app.askedUses }, set: { if !$0 { app.askedUses = true } })) {
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
        #if DEBUG
        .sheet(item: $debugSheet) { s in
            if case .ask(let scope) = s { AskSheet(scope: scope) }
        }
        .fullScreenCover(item: $debugCover) { s in
            switch s {
            case let .study(id, _): StudyView(lectureID: id, title: DebugSamples.title(of: id))
            case .notebook: NotebookEditor(id: DebugSamples.notebook())
            case .components(let page): ComponentGallery(page: page)
            default: WidgetGallery()
            }
        }
        #endif
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
            if !app.needsUses && !DebugLaunch.flag("-uses") { Task { await Reminders.setUp() } }
            upcoming = try? await app.api?.upcoming()
            await app.refreshInBackground()
            #if DEBUG
            if DebugLaunch.simulatesRecording { app.record(for: app.classNow(upcoming)) }
            switch DebugLaunch.show {
            case .addFiles: app.incoming = .files(DebugSamples.files(), className: "Calculus II", lecture: nil)
            case .importAudio: app.incoming = .audio(DebugSamples.audio())
            case .goodnotes: app.incoming = .goodnotes(DebugSamples.goodNotes())
            case .handwriting: app.incoming = .handwriting(className: "Calculus II", lecture: nil)
            case let s? where s.isCover: debugCover = s
            case .ask?: debugSheet = DebugLaunch.show
            default: break
            }
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

/// Launch arguments for pictures and testing in the simulator (debug builds only), where there's no camera to scan
/// with and no one to tap. Every screen can be opened from them; ios/DESIGN.md lists them all.
/// - `-demo` uses the demo library in the app; `-unpaired` forgets any library and shows setup (pairing), and with
///   `-pair-code` its second step; `-pair <address> <code>` pairs; `-library <address>` uses a library with no password.
/// - `-tab home|due|ask|settings|search` opens a tab; `-search <words>` opens Search with them typed.
/// - `-open lecture:<id>`, `class:<name>`, `assignment:<class>:<id>` or `search:<words>` pushes that screen on Home;
///   `-pane notes|transcript|files` picks a lecture's tab.
/// - `-show <screen>` opens a sheet: `record`, `ask`, `ask:lecture:<id>`, `ask:class:<name>`, `add-files`,
///   `import-audio`, `goodnotes`, `handwriting`, `notebook`, `study:<id>`, `quiz:<id>`, `uses`, `widgets`.
/// - `-record` records (in the simulator, made-up lines stand in for what's heard), `-ask "<question>"` asks it on
///   the Ask tab, `-quiet` never asks to send notifications.
/// A screen's own file can read a flag of its own with `DebugLaunch.flag("-x")` or `DebugLaunch.value("-x")`.
enum DebugLaunch {
    /// What follows `flag` (`offset` places on).
    static func value(_ flag: String, _ offset: Int = 1) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + offset) else { return nil }
        return args[i + offset]
        #else
        return nil
        #endif
    }

    /// Whether `flag` was given at all.
    static func flag(_ flag: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(flag)
        #else
        false
        #endif
    }

    static var tab: MainTabs.TabID? {
        switch value("-tab") {
        case "home", "library": .library
        case "due": .due
        case "ask": .ask
        case "settings": .settings
        case "search": .search
        default: value("-search") != nil ? .search : nil
        }
    }

    static var route: Route? {
        guard let v = value("-open") else { return nil }
        if v.hasPrefix("lecture:") { return .lecture(String(v.dropFirst(8))) }
        if v.hasPrefix("class:") { return .classDetail(String(v.dropFirst(6))) }
        if v.hasPrefix("search:") { return .search(String(v.dropFirst(7))) }
        if v.hasPrefix("assignment:"), let colon = v.lastIndex(of: ":"), let id = Int(v[v.index(after: colon)...]) {
            return .assignment(class: String(v[v.index(v.startIndex, offsetBy: 11)..<colon]), id: id)
        }
        return nil
    }

    /// The made-up lecture lines stand in for the microphone (the simulator has no speech model).
    static var simulatesRecording: Bool { flag("-record") || value("-show") == "record" }

    /// A lecture opens on this tab (`-pane transcript`), as LectureView's `Pane` names them.
    static var pane: String? { value("-pane")?.capitalized }

    /// Study opens on the quiz (`-show quiz:<id>`).
    static var studyQuiz: Bool { value("-show")?.hasPrefix("quiz") == true }

    #if DEBUG
    static var show: DebugScreen? { value("-show").flatMap(DebugScreen.init) }
    #endif

    @MainActor static func pairIfAsked(_ app: AppModel) async {
        #if DEBUG
        if flag("-unpaired") { app.forgetHere(); return }
        #endif
        if flag("-demo") { app.tryDemo(); return }
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
