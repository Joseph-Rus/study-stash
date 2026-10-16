import SwiftUI
import UIKit
import UserNotifications
import VisionKit

// Setup on the phone: everything a student sees before there's a library, in the desktop's setup look (MacSetup.axaml
// and SetupStyles.axaml): a big bold title, a plain sentence under it, steps numbered in outline circles, one ink
// button at the foot and at most one quiet link. No accent, no gradient, the real logo. On an iPad it's the desktop's
// setup window: the steps on the canvas at the left, the page a white sheet beside them.
//
// The way through (FLOWS.md, "First run"): Welcome → Open Study Stash on your computer (scan its code with this app,
// or type the address) → [This phone can't reach your computer yet, only if it can't] → Found {library}: the 6 digits
// → [What it's for, only if the library hasn't been told] → You're in: what to do next → Home. Or, from Welcome: Try
// it with sample classes → Home, with the demo library.

/// Setup: adding this phone to a library, or trying the sample classes.
struct PairView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var path: [SetupPage] = SetupDebug.path
    @State private var scanning = false
    /// Asking an address whether it's a library.
    @State private var finding = SetupDebug.page == "finding"
    /// What went wrong on the page that's open (a scan that isn't an address, a camera that's off).
    @State private var problem: String?
    @State private var address = SetupDebug.page == "address" ? "mac-mini.tail1234.ts.net" : ""
    /// What was scanned or typed last, for Try again.
    @State private var tried = ""
    /// This phone was added: the library, and what the last steps say about it.
    @State private var joined: Joined?

    var body: some View {
        Group {
            if sizeClass == .regular {
                SetupWindow(steps: steps, current: current) { stack }
            } else {
                stack
            }
        }
        .sheet(isPresented: $scanning) {
            ScanSheet { text in
                scanning = false
                Task { await find(text) }
            } typeInstead: {
                scanning = false
                path.append(.address)
            }
        }
        .task {
            // Pictures of the last steps: the demo library stands in for a library just joined.
            if SetupDebug.joins, joined == nil {
                joined = await Joined.read(base: DemoLibrary.base, library: SetupDebug.demo, needsUses: SetupDebug.page == "uses")
            }
        }
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            welcome
                .navigationDestination(for: SetupPage.self) { page in
                    switch page {
                    case .connect: connect
                    case .address: typeAddress
                    case .cantReach(let detail): cantReach(detail)
                    case let .code(base, library):
                        CodeEntry(base: base, library: library) { joined in
                            remember(joined)
                            path.append(joined.needsUses ? .uses : .done)
                        } differentComputer: {
                            path.removeLast()
                        }
                    case .uses:
                        if let joined { UsesStep(joined: joined) { path.append(.done) } } else { SetupWaiting() }
                    case .done:
                        if let joined { YoureIn(joined: joined) } else { SetupWaiting() }
                    }
                }
        }
        .onChange(of: path) { problem = nil }
    }

    // MARK: The pages before the library

    /// 1. Welcome.
    private var welcome: some View {
        SetupScreen(title: "Study Stash",
                    lede: "Your lectures, written up and filed. This app reads them from Study Stash on your computer, and records new ones.",
                    logo: true) {
            EmptyView()
        } foot: {
            Button { path.append(.connect) } label: { Text("Connect to my computer").frame(maxWidth: .infinity) }
                .buttonStyle(.pill(ink: true))
            Button("Try it with sample classes") { withAnimation(.smooth) { app.tryDemo() } }
                .buttonStyle(.textLink)
            Text("No computer with Study Stash yet? Get it at \(SetupLinks.siteName)")
                .textStyle(.meta)
                .foregroundStyle(.inkMuted)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.top, 4)
        }
    }

    /// 2. On your computer.
    private var connect: some View {
        SetupScreen(step: "Step 1 of 2", title: "Open Study Stash on your computer") {
            VStack(alignment: .leading, spacing: 20) {
                NumberedSteps {
                    StepRow(1) { Text("Open Settings, then Phone.") }
                    StepRow(2) { Text("Choose Add a phone. It shows a QR code.") }
                }
                if let problem { ProblemText(problem) }
            }
        } foot: {
            Text("Use this button, not the Camera app.")
                .textStyle(.meta)
                .foregroundStyle(.inkMuted)
            Button { scan() } label: {
                HStack(spacing: 8) {
                    if finding {
                        ProgressView().tint(.surface)
                        Text("Finding your library…")
                    } else {
                        Icon("qr_code_scanner", size: 18)
                        Text("Scan the QR code")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(ink: true))
            .disabled(finding)
            Button("Type the address instead") { typeAddressInstead() }
                .buttonStyle(.textLink)
                .disabled(finding)
        }
    }

    /// 2, typed: the address under the computer's QR code.
    private var typeAddress: some View {
        SetupScreen(step: "Step 1 of 2", title: "Type the address",
                    lede: "On your computer, open Settings, then Phone, then Add a phone, and hold the pointer over the QR code: its address shows.") {
            VStack(alignment: .leading, spacing: 16) {
                AddressField(address: $address) { Task { await find(address) } }
                if let problem { ProblemText(problem) }
            }
        } foot: {
            Button { Task { await find(address) } } label: {
                HStack(spacing: 8) {
                    if finding { ProgressView().tint(.surface) }
                    Text(finding ? "Finding your library…" : "Find it")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(ink: true))
            .disabled(finding || address.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// 3. Can't reach your computer: only when finding the library failed.
    private func cantReach(_ detail: String) -> some View {
        SetupScreen(step: "Step 1 of 2", title: "This phone can't reach your computer yet",
                    lede: "Your phone reaches your computer through Tailscale. Open the Tailscale app on this phone, sign in with the same account as your computer, and turn it on.") {
            Text(detail)
                .textStyle(.summary)
                .foregroundStyle(.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        } foot: {
            Button { Task { await find(tried) } } label: {
                HStack(spacing: 8) {
                    if finding { ProgressView().tint(.surface) }
                    Text(finding ? "Finding your library…" : "Try again")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(ink: true))
            .disabled(finding)
            Link("Get Tailscale", destination: SetupLinks.tailscale)
                .buttonStyle(.textLink)
        }
    }

    // MARK: What the pages do

    /// The steps the iPad's side shows ("What it's for" once it's known to be one), and which one is open.
    private var steps: [String] {
        ["Welcome", "Your computer", "The code"] + (joined?.needsUses == true ? ["What it's for"] : []) + ["You're in"]
    }

    private var current: Int {
        switch path.last {
        case nil: 0
        case .connect?, .address?, .cantReach?: 1
        case .code?: 2
        case .uses?: 3
        case .done?: steps.count - 1
        }
    }

    private func scan() {
        problem = nil
        guard DataScannerViewController.isSupported else {
            // No camera that reads codes (an old phone, the simulator): type it.
            path.append(.address)
            return
        }
        guard DataScannerViewController.isAvailable else {
            problem = "Study Stash can't use the camera. Allow it in the Settings app, then Study Stash, or type the address instead."
            return
        }
        scanning = true
    }

    private func typeAddressInstead() {
        problem = nil
        path.append(.address)
    }

    /// Try each address the scan or the typing gave, best first, until one is a library. Found: the code. Not found:
    /// the Tailscale page (or it stays, saying what the library said this time).
    private func find(_ text: String) async {
        let candidates = LibraryAddress.candidates(from: text)
        guard !candidates.isEmpty else {
            problem = "That isn't a Study Stash address. Scan the QR code on your computer, or check the address."
            return
        }
        tried = text
        finding = true
        problem = nil
        defer { finding = false }
        var said = APIError.unreachableLibrary.detail
        for base in candidates {
            do {
                let me = try await APIClient(base: base, session: AppModel.session).me()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if case .cantReach? = path.last { path.removeLast() }
                path.append(.code(base: base, library: me.library))
                return
            } catch {
                said = (error as? APIError)?.detail ?? said
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        if case .cantReach? = path.last { path.removeLast() }
        path.append(.cantReach(detail: said))
    }

    /// Paired: this phone keeps the library from now on, even if the app closes before Home (the code's spent). The
    /// app itself goes in when the student leaves setup (`AppModel.paired`, from You're in).
    private func remember(_ joined: Joined) {
        self.joined = joined
        UserDefaults.standard.set(joined.base.absoluteString, forKey: AppModel.baseKey)
        UserDefaults.standard.set(joined.library.name, forKey: AppModel.nameKey)
    }
}

/// The pages after Welcome.
enum SetupPage: Hashable {
    case connect
    case address
    case cantReach(detail: String)
    case code(base: URL, library: Me.Library)
    case uses
    case done
}

/// Where a student gets Study Stash for their computer, and Tailscale for the phone.
enum SetupLinks {
    static let siteName = "study-stash-app.web.app"
    static let tailscale = URL(string: "https://apps.apple.com/app/tailscale/id1470499037")!
}

/// The library this phone just joined, and what the last steps say from it: whether it's been told what it's for,
/// the next class on its calendar and its newest lecture.
struct Joined: Hashable {
    var base: URL
    var library: Me.Library
    var needsUses: Bool
    var next: UpcomingEvent?
    var newest: LectureSummary?

    /// Read what the last steps need, a few seconds at most for each (without them the steps say less).
    @MainActor static func read(base: URL, library: Me.Library, needsUses: Bool? = nil) async -> Joined {
        let api = APIClient(base: base, session: AppModel.session)
        async let overview = within(4) { try await api.library() }
        async let upcoming = within(4) { try await api.upcoming() }
        async let newest = within(4) { try await api.lectures(limit: 1) }
        let (o, u, n) = await (overview, upcoming, newest)
        // The next class on the calendar (one the library matched to a class, else the next event at all).
        let now = Date.now
        let coming = (u?.events ?? [])
            .filter { !$0.allDay && (Format.parse($0.end) ?? .distantPast) > now }
            .sorted { (Format.parse($0.start) ?? .distantFuture) < (Format.parse($1.start) ?? .distantFuture) }
        return Joined(base: base, library: library, needsUses: needsUses ?? (o?.uses?.isEmpty == true),
                      next: coming.first { $0.class != nil } ?? coming.first, newest: n?.first)
    }

    /// `work`, or nil if it fails or takes longer than `seconds`.
    private static func within<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

// MARK: - 4. The code

/// "Found {library}": the six digits, in boxes, sent as soon as the sixth is typed, and the name this phone goes by.
private struct CodeEntry: View {
    var base: URL
    var library: Me.Library
    var joined: (Joined) -> Void
    var differentComputer: () -> Void

    @State private var code = SetupDebug.page == "typing" ? "042" : ""
    @State private var name = UIDevice.current.name
    @State private var busy = false
    @State private var problem: String? = SetupDebug.page == "wrong" ? CodeEntry.wrongCode : nil
    @State private var shakes: CGFloat = 0
    @FocusState private var focus: Field?

    private enum Field { case code, name }
    /// What the library says to a wrong code (LibraryWeb.Devices.cs), for the pictures.
    static let wrongCode = "That code isn't right, or it's more than ten minutes old. Make a new one in Study Stash's Settings."

    var body: some View {
        SetupScreen(step: "Step 2 of 2", title: "Found \(library.name)",
                    lede: "Type the 6 digits your computer shows beside the QR code.") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .leading) {
                        TextField("", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focus, equals: .code)
                            .opacity(0.02)
                            .accessibilityLabel("6-digit code")
                            .onChange(of: code) { _, new in
                                let digits = String(new.filter(\.isNumber).prefix(6))
                                if digits != new { code = digits }
                                if !digits.isEmpty { problem = nil }
                                if digits.count == 6 { Task { await pair() } }
                            }
                        CodeBoxes(code: code, focused: focus == .code)
                            .allowsHitTesting(false)
                    }
                    .contentShape(.rect)
                    .onTapGesture { focus = .code }
                    .modifier(Shake(times: shakes))

                    if let problem {
                        // A refusal, in the library's own words: the late red, as the plan has errors.
                        Text(problem).textStyle(.body).foregroundStyle(.late)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("This phone's name").font(.atkinson(14, .bold, relativeTo: .subheadline)).foregroundStyle(.ink)
                    TextField(UIDevice.current.name, text: $name)
                        .textStyle(.body)
                        .foregroundStyle(.ink)
                        .focused($focus, equals: .name)
                        .submitLabel(.done)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(.surface, in: .rect(cornerRadius: Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.control)
                                .strokeBorder(focus == .name ? Color.ink : .line, lineWidth: focus == .name ? 1.5 : 1)
                        }
                    Text("Your computer lists it under Phones by this name.").textStyle(.meta).foregroundStyle(.inkMuted)
                }
            }
        } foot: {
            Button { Task { await pair() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.surface) }
                    Text(busy ? "Connecting…" : "Connect")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(ink: true))
            .disabled(code.count != 6 || busy)
            Button("Use a different computer", action: differentComputer)
                .buttonStyle(.textLink)
                .disabled(busy)
        }
        .onAppear { if SetupDebug.page != "wrong" { focus = .code } }
    }

    private func pair() async {
        guard code.count == 6, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let api = APIClient(base: base, session: AppModel.session)
            let typed = name.trimmingCharacters(in: .whitespaces)
            _ = try await api.pair(code: code, name: typed.isEmpty ? UIDevice.current.name : typed)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            focus = nil
            joined(await Joined.read(base: base, library: library))
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            problem = (error as? APIError)?.detail ?? "Couldn't reach your library. Try again."
            withAnimation(.default) { shakes += 1 }
            code = ""
            focus = .code
        }
    }
}

/// The six boxes, three and three as the computer shows the code ("042 917"); the next one to fill ringed in ink, with
/// the caret in it.
private struct CodeBoxes: View {
    var code: String
    var focused: Bool
    @ScaledMetric(relativeTo: .title) private var width: CGFloat = 44

    var body: some View {
        let chars = Array(code)
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { i in
                box(i < chars.count ? String(chars[i]) : "", caret: focused && i == chars.count)
                    .padding(.leading, i == 3 ? 10 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func box(_ digit: String, caret: Bool) -> some View {
        let w = min(width, 52)
        return Text(digit)
            .font(.atkinson(26, .bold, relativeTo: .title))
            .foregroundStyle(.ink)
            .frame(width: w, height: w * 1.3)
            .background(.surface, in: .rect(cornerRadius: Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(caret ? Color.ink : .line, lineWidth: caret ? 1.5 : 1)
            }
            .overlay { if caret { Caret() } }
    }
}

/// A text caret, blinking (steady with Reduce Motion).
private struct Caret: View {
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var on = true
    var body: some View {
        Rectangle().fill(.ink).frame(width: 2, height: 26)
            .opacity(on ? 1 : 0)
            .task {
                guard !still else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    on.toggle()
                }
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

// MARK: - 5. What it's for

/// What the library is for, asked once here (never as a sheet over Home): Settings' "What it's for" choices, any that
/// fit. School brings classes, Canvas and what's due; anything else gets folders.
private struct UsesStep: View {
    @Environment(AppModel.self) private var app
    var joined: Joined
    var next: () -> Void

    @State private var picked: Set<String> = []
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        SetupScreen(title: "What will you use Study Stash for?",
                    lede: "Pick any that fit. School brings in classes, Canvas and what's due; anything else gets folders.") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(UsesView.kinds) { k in
                    let on = picked.contains(k.id)
                    ChoiceCard(icon: Self.icon(k.id), title: k.title, about: k.about, on: on) {
                        if on { picked.remove(k.id) } else { picked.insert(k.id) }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
                if let problem { ProblemText(problem).padding(.top, 6) }
            }
        } foot: {
            Button { Task { await save() } } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.surface) }
                    Text(saving ? "Saving…" : "Continue")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(ink: true))
            .disabled(picked.isEmpty || saving)
            // Skipped, Home offers it once later ("Tell Study Stash what it's for").
            Button("Skip for now", action: next).buttonStyle(.textLink).disabled(saving)
        }
        .navigationBarBackButtonHidden()
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let list = UsesView.kinds.map(\.id).filter(picked.contains)
        do {
            _ = try await APIClient(base: joined.base, session: AppModel.session).setUses(list)
            app.askedUses = true
            next()
        } catch {
            problem = (error as? APIError)?.detail ?? "Couldn't save that. Try again."
        }
    }

    /// Each kind's icon, the desktop's.
    static func icon(_ id: String) -> String {
        switch id {
        case "student": "school"
        case "work": "work"
        case "research": "science"
        case "creative": "palette"
        default: "person"
        }
    }
}

// MARK: - 6. You're in

/// The last step: the library's name and what to do next, each a button (FLOWS.md, "You're in").
private struct YoureIn: View {
    @Environment(AppModel.self) private var app
    var joined: Joined

    @State private var reminders: UNAuthorizationStatus?

    var body: some View {
        SetupScreen(title: "You're in", lede: "This phone reads \(joined.library.name).") {
            VStack(alignment: .leading, spacing: 0) {
                NextRow(icon: "mic", title: "Record your next class", about: recordAbout, first: true) { goHome() }
                NextRow(icon: remindersOn ? "check_circle" : "notifications",
                        title: remindersOn ? "Reminders are on" : "Get a reminder when a class starts",
                        about: remindersAbout) { Task { await askReminders() } }
                if let newest = joined.newest {
                    NextRow(icon: "description", title: "Read your latest notes", about: about(newest)) { goHome(open: newest.id) }
                }
            }
        } foot: {
            Button { goHome() } label: { Text("Go to Home").frame(maxWidth: .infinity) }
                .buttonStyle(.pill(ink: true))
        }
        .navigationBarBackButtonHidden()
        .task { reminders = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }

    /// "Calculus II starts tomorrow at 9:00 AM. On Home, tap it when it starts." (or without a calendar, where Record is).
    private var recordAbout: String {
        guard let e = joined.next, let start = Format.parse(e.start) else { return "Tap Record at the bottom of any page." }
        let name = e.class ?? e.title
        let now = Date.now
        if start <= now { return "\(name) is on now. On Home, tap it to record it." }
        let when: String = if start.timeIntervalSince(now) < 3600 {
            Format.inMinutes(start.timeIntervalSince(now))
        } else {
            switch Format.daysBetween(now, start) {
            case 0: "today at \(Format.time(start))"
            case 1: "tomorrow at \(Format.time(start))"
            default: "on \(Format.date(start)) at \(Format.time(start))"
            }
        }
        return "\(name) starts \(when). On Home, tap it when it starts."
    }

    private var remindersOn: Bool { reminders == .authorized || reminders == .provisional }

    private var remindersAbout: String {
        switch reminders {
        case .authorized?, .provisional?, .ephemeral?: "Study Stash tells you when a class starts, and before work is due."
        case .denied?: "They're off for Study Stash. Turn them on in the Settings app, then Study Stash."
        default: "So you can record it in one tap, and before work is due."
        }
    }

    private func about(_ l: LectureSummary) -> String {
        let title = l.title ?? Nouns.untitled(folder: l.class, date: l.date)
        guard let d = Format.parse(l.date) else { return title }
        return "\(title) · \(Format.day(d))"
    }

    /// Asked here, with the reason already said; never cold anywhere else. Refused before, it's the Settings app.
    private func askReminders() async {
        switch reminders {
        case .denied?:
            if let url = URL(string: UIApplication.openSettingsURLString) { _ = await UIApplication.shared.open(url) }
        case .notDetermined?, nil:
            await Reminders.setUp()
            reminders = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        default:
            break
        }
    }

    /// Into the app, on Home (and the newest lecture, when that's where the student's going).
    private func goHome(open lecture: String? = nil) {
        withAnimation(.smooth) { app.paired(base: joined.base, library: joined.library) }
        guard let lecture else { return }
        // FLOWS: after the merge with iphone-look this is `app.go(.lecture(lecture), tab: .home, root: true)`. Until
        // then Home takes a pending route only once it's on screen, so it's set once Home is up.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            app.pendingRoute = .lecture(lecture)
        }
    }
}

/// A next step on "You're in" (the desktop's "What to do next" rows): an icon, a bold line and a muted one under it,
/// the whole row a button, hairlines between.
private struct NextRow: View {
    var icon: String
    var title: String
    var about: String
    var first = false
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !first { Rule() }
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Icon(icon, size: 20).foregroundStyle(.ink)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.atkinson(15.5, .bold, relativeTo: .body)).foregroundStyle(.ink)
                        Text(about).textStyle(.summary).foregroundStyle(.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Icon("chevron_right", size: 16).foregroundStyle(.inkSubtle)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                }
                .multilineTextAlignment(.leading)
                .padding(.vertical, 16)
            }
            .buttonStyle(.row)
            .accessibilityElement(children: .combine)
        }
    }
}

/// While the last steps' details are read (only ever a moment).
private struct SetupWaiting: View {
    var body: some View {
        ProgressView().tint(.inkSubtle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .page()
            .navigationBarBackButtonHidden()
    }
}

// MARK: - The page

/// One page of setup, as the desktop's: an optional logo, an optional "Step 1 of 2" small and grey, the title, a
/// sentence under it, what the page is for, and its buttons at the foot (the ink one full width, a quiet link under it).
private struct SetupScreen<Content: View, Foot: View>: View {
    var step: String?
    var title: String
    var lede: String?
    var logo = false
    @ViewBuilder var content: Content
    @ViewBuilder var foot: Foot
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let regular = sizeClass == .regular
        let margin = regular ? Space.s10 : Space.pageCompact
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if logo { StudyStashLogo(size: 72).padding(.bottom, 28) }
                if let step {
                    Text(step).textStyle(.meta).foregroundStyle(.inkSubtle).padding(.bottom, 6)
                }
                Text(title).textStyle(logo ? .date : .docTitle).foregroundStyle(.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let lede {
                    Text(lede).textStyle(.lede).foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                content.padding(.top, 28)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, margin)
            .padding(.top, logo ? 40 : 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 14) { foot }
                .frame(maxWidth: regular ? 560 : .infinity)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, margin)
                .padding(.top, 12)
                .padding(.bottom, regular ? 24 : 8)
                .background(Color.surface)
        }
        .foregroundStyle(.ink)
        .page()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// A choice on the page (the desktop's `Button.choice`): a white panel with a hairline, its icon, a bold title and a
/// line about it, and its mark; a chosen one ringed in ink, its mark an ink circle with a tick.
private struct ChoiceCard: View {
    var icon: String
    var title: String
    var about: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Icon(icon, size: 22).foregroundStyle(on ? Color.ink : .inkMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.atkinson(15.5, .bold, relativeTo: .body)).foregroundStyle(.ink)
                    Text(about).font(.atkinson(13.5, relativeTo: .footnote)).lineSpacing(2).foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Tick(on: on)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 68)
        }
        .buttonStyle(ChoiceStyle(on: on))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The choice's panel: ringed in ink when chosen; pressed, its hairline darkens (colour only).
private struct ChoiceStyle: ButtonStyle {
    var on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.surface, in: .rect(cornerRadius: Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.panel)
                    .strokeBorder(on ? Color.ink : configuration.isPressed ? .inkSubtle : .line, lineWidth: on ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: Radius.panel))
    }
}

/// A choice's mark: a grey ring, or an ink circle with the page's colour ticked in it.
private struct Tick: View {
    var on: Bool
    var body: some View {
        ZStack {
            if on {
                Circle().fill(.ink)
                Icon("check", size: 13).foregroundStyle(.surface)
            } else {
                Circle().strokeBorder(.inkSubtle, lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// Steps to follow, numbered in outline circles.
private struct NumberedSteps<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
    }
}

/// One numbered step: its number in an ink ring, the words beside it.
private struct StepRow<Content: View>: View {
    var number: Int
    var content: Content

    init(_ number: Int, @ViewBuilder content: () -> Content) {
        self.number = number
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            StepNumber(number: number)
            content
                .textStyle(.lede)
                .foregroundStyle(.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A step's number in an outline circle (the desktop's `Border.num`, a size up for a phone).
private struct StepNumber: View {
    var number: Int
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 26

    var body: some View {
        Text("\(number)")
            .font(.atkinson(13, .bold, relativeTo: .footnote))
            .foregroundStyle(.ink)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.ink, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// The address, typed: a white field with a hairline, ringed in ink while the caret's in it.
private struct AddressField: View {
    @Binding var address: String
    var submit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Address").font(.atkinson(14, .bold, relativeTo: .subheadline)).foregroundStyle(.ink)
            TextField("mac-mini.tail1234.ts.net", text: $address)
                .textStyle(.body)
                .foregroundStyle(.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .onSubmit(submit)
                .focused($focused)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.surface, in: .rect(cornerRadius: Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(focused ? Color.ink : .line, lineWidth: focused ? 1.5 : 1)
                }
        }
        .onAppear { if address.isEmpty { focused = true } }
    }
}

/// Something went wrong on a page, said plainly, in the late red the plan gives errors.
private struct ProblemText: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).textStyle(.body).foregroundStyle(.late).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The iPad's window

/// On an iPad, setup is the desktop's setup window: which setup this is and its steps on the canvas at the left (the
/// open one a white chip, the ones done ticked), and the page a white sheet with a hairline round it.
private struct SetupWindow<Content: View>: View {
    var steps: [String]
    var current: Int
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Icon("smartphone", size: 16).foregroundStyle(.inkSubtle)
                    Text("Phone setup").textStyle(.group).foregroundStyle(.inkMuted)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, name in
                    SideStep(number: i + 1, name: name, state: i < current ? .done : i == current ? .open : .toDo)
                }
            }
            .frame(width: 240, alignment: .leading)
            .padding(.top, 24)
            .padding(.leading, 6)

            content
                .clipShape(.rect(cornerRadius: Radius.pane))
                .overlay(RoundedRectangle(cornerRadius: Radius.pane).strokeBorder(.line))
        }
        .padding(8)
        .background(Color.canvas.ignoresSafeArea())
    }
}

/// A step in the iPad's side (the desktop's `Border.step`): its number in a grey ring, or a tick once done; the open
/// one a white chip, its words bold in ink.
private struct SideStep: View {
    enum Mark { case done, open, toDo }
    var number: Int
    var name: String
    var state: Mark

    var body: some View {
        HStack(spacing: 10) {
            if state == .done {
                Icon("check_circle", size: 18).foregroundStyle(.inkMuted)
            } else {
                Text("\(number)")
                    .font(.atkinson(10, .bold, relativeTo: .caption2))
                    .foregroundStyle(state == .open ? Color.ink : .inkSubtle)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(state == .open ? Color.ink : .inkSubtle, lineWidth: 1.5))
            }
            Text(name)
                .font(.atkinson(15, state == .open ? .bold : .medium, relativeTo: .body))
                .foregroundStyle(state == .open ? Color.ink : .inkMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background {
            if state == .open {
                RoundedRectangle(cornerRadius: Radius.control).fill(.surface)
                RoundedRectangle(cornerRadius: Radius.control).strokeBorder(.line)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .done ? "Done" : state == .open ? "Now" : "")
    }
}

// MARK: - Scanning

/// The camera, under a bar with Cancel, with a line at the foot saying what to point it at and a way to type the
/// address instead.
private struct ScanSheet: View {
    var found: (String) -> Void
    var typeInstead: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScanner(found: found)
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Point it at the QR code in Study Stash on your computer.")
                            .textStyle(.body).foregroundStyle(.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Type the address instead", action: typeInstead).buttonStyle(.textLink)
                    }
                    .padding(16)
                    .frame(maxWidth: 480, alignment: .leading)
                    .background(.surface, in: .rect(cornerRadius: Radius.panel))
                    .lifted(.float, in: RoundedRectangle(cornerRadius: Radius.panel))
                    .padding(.horizontal, Space.pageCompact)
                    .padding(.bottom, 12)
                }
                .navigationTitle("Scan the QR code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("Cancel").textStyle(.nav) }
                    }
                }
        }
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

// MARK: - Pictures

/// Setup's own launch arguments (debug builds), for pictures of each page and state with `-unpaired`:
/// `-pair-page connect | finding | address | cant-reach | code | typing | wrong | uses | done` (`-pair-code` is
/// `-pair-page code`). The code pages use the demo library's address, which never pairs; `uses` and `done` read the
/// demo library as if this phone had just joined it.
private enum SetupDebug {
    static let page: String? = DebugLaunch.flag("-pair-code") ? "code" : DebugLaunch.value("-pair-page")
    static let demo = Me.Library(name: "Demo library", version: "demo")
    /// The last steps, which need a library joined.
    static var joins: Bool { page == "uses" || page == "done" }

    static var path: [SetupPage] {
        switch page {
        case "connect", "finding": [.connect]
        case "address": [.connect, .address]
        case "cant-reach": [.connect, .cantReach(detail: APIError.unreachableLibrary.detail)]
        case "code", "typing", "wrong": [.connect, .code(base: DemoLibrary.base, library: demo)]
        case "uses": [.uses]
        case "done": [.done]
        default: []
        }
    }
}
