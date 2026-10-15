import AppKit
import EventKit
import Observation
import UserNotifications

/// A calendar event with a call link.
struct Meeting: Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var link: URL

    var service: String { MeetingLink.service(of: link) ?? "Call" }
}

/// Finds call links in calendar events.
enum MeetingLink {
    /// Hosts of call links, and what each is called.
    static let services: [(host: String, name: String)] = [
        ("meet.google.com", "Google Meet"),
        ("zoom.us", "Zoom"),
        ("zoomgov.com", "Zoom"),
        ("teams.microsoft.com", "Teams"),
        ("teams.live.com", "Teams"),
        ("webex.com", "Webex"),
        ("facetime.apple.com", "FaceTime"),
        ("whereby.com", "Whereby"),
    ]

    /// The first call link in these texts, in order: an event's URL, location, and notes.
    static func find(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap(\.self) {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let url = match.url, service(of: url) != nil { return url }
            }
        }
        return nil
    }

    /// The service a call link opens, or nil if it isn't a call link.
    static func service(of url: URL) -> String? {
        guard ["https", "http"].contains(url.scheme?.lowercased()), let host = url.host()?.lowercased(),
              url.path().count > 1 else { return nil }
        guard let name = services.first(where: { host == $0.host || host.hasSuffix("." + $0.host) })?.name else { return nil }
        // Zoom's other pages, like zoom.us/download, aren't calls.
        if name == "Zoom" { return ["/j/", "/my/", "/w/", "/s/"].contains { url.path().hasPrefix($0) } ? name : nil }
        return name
    }
}

/// Watches the calendar for calls and, a minute before each, offers to join it and take notes.
@MainActor @Observable
final class Meetings {
    struct CalendarChoice: Identifiable, Hashable {
        var id: String
        var title: String
    }

    /// Remind before calls on the calendar.
    var on: Bool {
        didSet {
            UserDefaults.standard.set(on, forKey: Keys.meetings)
            on ? begin() : end()
        }
    }

    /// The calendar to watch. nil is all of them.
    var calendarID: String? {
        didSet {
            UserDefaults.standard.set(calendarID, forKey: Keys.meetingCalendar)
            check()
        }
    }

    private(set) var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    private(set) var notificationsAllowed = true
    private(set) var calendars: [CalendarChoice] = []
    /// A call starting within 5 minutes or going on now.
    private(set) var current: Meeting?

    /// Called when someone picks Take notes.
    @ObservationIgnored var onTakeNotes: (Meeting) -> Void = { _ in }
    @ObservationIgnored private let events = EKEventStore()
    @ObservationIgnored private let notifications = NotificationDelegate()
    @ObservationIgnored private var reminded: Set<String> = []
    @ObservationIgnored private var loop: Task<Void, Never>?

    nonisolated private static let category = "meeting"
    nonisolated private static let takeNotes = "takeNotes"

    init() {
        on = UserDefaults.standard.bool(forKey: Keys.meetings)
        calendarID = UserDefaults.standard.string(forKey: Keys.meetingCalendar)
    }

    /// Called once at launch. The delegate must be set before a click on an old reminder arrives.
    func start() {
        let center = UNUserNotificationCenter.current()
        notifications.onTakeNotes = { [weak self] in self?.onTakeNotes($0) }
        center.delegate = notifications
        center.setNotificationCategories([UNNotificationCategory(
            identifier: Self.category,
            actions: [UNNotificationAction(identifier: Self.takeNotes, title: "Take notes", options: [.foreground])],
            intentIdentifiers: []
        )])
        if on { begin() }
    }

    private func begin() {
        guard loop == nil else { return }
        loop = Task {
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                _ = try? await events.requestFullAccessToEvents()
            }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            while !Task.isCancelled {
                // Either can be granted later in System Settings, with no callback.
                calendarAccess = EKEventStore.authorizationStatus(for: .event)
                notificationsAllowed = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
                check()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func end() {
        loop?.cancel()
        loop = nil
        current = nil
    }

    /// Finds the current call and reminds about one starting within a minute.
    private func check() {
        guard on, calendarAccess == .fullAccess else { return }
        let all = events.calendars(for: .event)
        calendars = all.map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title) }.sorted { $0.title < $1.title }
        let watched = calendarID.map { id in all.filter { $0.calendarIdentifier == id } } ?? all
        guard !watched.isEmpty else { current = nil; return }
        let now = Date.now
        let predicate = events.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(5 * 60), calendars: watched)
        let meetings = events.events(matching: predicate).compactMap(Self.meeting).filter { $0.end > now }.sorted { $0.start < $1.start }
        // The latest one to have started, or else the next one.
        current = meetings.last { $0.start <= now } ?? meetings.first
        for meeting in meetings where Self.isDue(meeting, now: now) && !reminded.contains(meeting.id) {
            reminded.insert(meeting.id)
            remind(meeting)
        }
    }

    /// Remind from a minute before until two minutes after the start, in case the Mac was asleep.
    nonisolated static func isDue(_ meeting: Meeting, now: Date) -> Bool {
        let lead = meeting.start.timeIntervalSince(now)
        return lead <= 60 && lead > -120
    }

    private static func meeting(_ event: EKEvent) -> Meeting? {
        guard !event.isAllDay, event.status != .canceled,
              event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined,
              let link = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]) else { return nil }
        // Every repeat of an event shares its identifier, so add the start.
        let id = "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(event.startDate.timeIntervalSince1970)"
        return Meeting(id: id, title: event.title ?? "Call", start: event.startDate, end: event.endDate, link: link)
    }

    private func remind(_ meeting: Meeting) {
        let content = UNMutableNotificationContent()
        content.title = meeting.title
        content.body = "\(meeting.service) at \(meeting.start.formatted(date: .omitted, time: .shortened))"
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = meeting.userInfo
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: meeting.id, content: content, trigger: nil))
    }

    /// Where to fix what's blocking reminders: calendar access first, then notifications.
    func openSettings() {
        let pane = calendarAccess == .fullAccess
            ? "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        NSWorkspace.shared.open(URL(string: pane)!)
    }

    /// Hands a click on a reminder to Parrot. Clicking the reminder itself also takes notes.
    @MainActor private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
        var onTakeNotes: (Meeting) -> Void = { _ in }

        nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            guard [Meetings.takeNotes, UNNotificationDefaultActionIdentifier].contains(response.actionIdentifier),
                  let meeting = Meeting(userInfo: response.notification.request.content.userInfo) else { return }
            await MainActor.run { onTakeNotes(meeting) }
        }
    }
}

extension Meeting {
    var userInfo: [String: Any] {
        ["id": id, "title": title, "start": start.timeIntervalSince1970, "end": end.timeIntervalSince1970, "link": link.absoluteString]
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["id"] as? String, let title = userInfo["title"] as? String,
              let start = userInfo["start"] as? Double, let end = userInfo["end"] as? Double,
              let link = (userInfo["link"] as? String).flatMap(URL.init(string:)) else { return nil }
        self.init(id: id, title: title, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end), link: link)
    }
}
