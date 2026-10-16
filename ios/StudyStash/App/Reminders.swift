import BackgroundTasks
import Foundation
import UserNotifications

/// What the phone tells the student on its own (the library is on their computer, so nothing is pushed): a class
/// starting, with Record; work due the evening before and two hours before; and a lecture recorded here whose notes
/// are written. Scheduled again whenever the app has a fresh look at the library, and in the background.
@MainActor
enum Reminders {
    static let center = UNUserNotificationCenter.current()
    static let refreshTask = "app.studystash.ios.refresh"

    enum Kind: String { case classStart = "class", due, notes }

    struct Settings {
        static var classStart: Bool {
            get { UserDefaults.standard.object(forKey: "remind.class") as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: "remind.class") }
        }
        static var due: Bool {
            get { UserDefaults.standard.object(forKey: "remind.due") as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: "remind.due") }
        }
        static var notes: Bool {
            get { UserDefaults.standard.object(forKey: "remind.notes") as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: "remind.notes") }
        }
    }

    /// Ask once, and say what Record does.
    static func setUp() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-quiet") { return }
        #endif
        let record = UNNotificationAction(identifier: "record", title: "Record", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Kind.classStart.rawValue, actions: [record], intentIdentifiers: []),
        ])
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Every class start and due reminder from what the library said last, replacing those scheduled before.
    static func schedule(upcoming: Upcoming?, due: DueList?, classOf: (UpcomingEvent) -> String?) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !$0.hasPrefix(Kind.notes.rawValue) })
        var requests: [UNNotificationRequest] = []
        let now = Date.now

        if Settings.classStart {
            for e in upcoming?.events ?? [] where !e.allDay {
                guard let start = Format.parse(e.start), start > now, let cls = classOf(e) else { continue }
                let c = UNMutableNotificationContent()
                c.title = "\(cls) is starting"
                c.body = [e.location, "Tap Record to take notes for you."].compactMap { $0 }.joined(separator: " · ")
                c.categoryIdentifier = Kind.classStart.rawValue
                c.userInfo = ["class": cls]
                c.interruptionLevel = .timeSensitive
                requests.append(request("\(Kind.classStart.rawValue)-\(e.id)", c, at: start.addingTimeInterval(-60)))
            }
        }

        if Settings.due {
            let open = (due?.groups ?? []).filter { ["week", "later"].contains($0.key) }.flatMap(\.items)
            for item in open {
                guard let at = Format.parse(item.due), at > now else { continue }
                let c = UNMutableNotificationContent()
                c.title = item.name
                c.userInfo = ["class": item.class, "assignment": item.id]
                let eveningBefore = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0,
                                                          of: Calendar.current.date(byAdding: .day, value: -1, to: at)!)!
                if eveningBefore > now {
                    c.body = "\(item.class) · due tomorrow, \(Format.time(at))"
                    requests.append(request("\(Kind.due.rawValue)-\(item.id)-eve", c, at: eveningBefore))
                }
                let twoHours = at.addingTimeInterval(-7200)
                if twoHours > now, let c2 = c.mutableCopy() as? UNMutableNotificationContent {
                    c2.body = "\(item.class) · due in 2 hours, at \(Format.time(at))"
                    c2.interruptionLevel = .timeSensitive
                    requests.append(request("\(Kind.due.rawValue)-\(item.id)-2h", c2, at: twoHours))
                }
            }
        }
        #if DEBUG
        NSLog("[reminders] %d class starts and due reminders", requests.count)
        #endif
        // iOS keeps at most 64: the soonest.
        for r in requests.sorted(by: { fireDate($0) < fireDate($1) }).prefix(60) { try? await center.add(r) }
    }

    private static func request(_ id: String, _ content: UNNotificationContent, at date: Date) -> UNNotificationRequest {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    private static func fireDate(_ r: UNNotificationRequest) -> Date {
        (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }

    // MARK: notes written

    /// Lectures sent from this phone whose notes are now written: say so, once each.
    static func checkNotes(api: APIClient) async {
        guard Settings.notes else { return }
        let sent = RecordingStore.shared.recordings.filter { $0.state == .sent && $0.started > .now.addingTimeInterval(-3 * 86_400) }
        var told = Set(UserDefaults.standard.stringArray(forKey: "remind.notesTold") ?? [])
        for r in sent where !told.contains(r.id) {
            guard let l = try? await api.lecture(r.id), l.status == "done" else { continue }
            let c = UNMutableNotificationContent()
            c.title = "Notes are ready"
            c.body = l.displayTitle + (l.topics.isEmpty ? "" : " · " + l.topics.prefix(3).joined(separator: ", "))
            c.userInfo = ["lecture": r.id]
            try? await center.add(UNNotificationRequest(identifier: "\(Kind.notes.rawValue)-\(r.id)", content: c, trigger: nil))
            told.insert(r.id)
        }
        UserDefaults.standard.set(Array(told.suffix(200)), forKey: "remind.notesTold")
    }

    // MARK: in the background

    static func scheduleRefresh() {
        let r = BGAppRefreshTaskRequest(identifier: refreshTask)
        r.earliestBeginDate = .now.addingTimeInterval(20 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

/// Notifications tapped: Record starts recording the class; a lecture or assignment opens.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    @MainActor weak var app: AppModel?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let cls = info["class"] as? String
        let action = response.actionIdentifier
        let kind = response.notification.request.content.categoryIdentifier
        let lecture = info["lecture"] as? String
        let assignment = info["assignment"] as? Int
        await MainActor.run {
            guard let app else { return }
            if action == "record" || kind == Reminders.Kind.classStart.rawValue {
                app.record(for: cls)
            } else if let lecture {
                app.pendingRoute = .lecture(lecture)
            } else if let cls, let id = assignment {
                app.pendingRoute = .assignment(class: cls, id: id)
            }
        }
    }
}
