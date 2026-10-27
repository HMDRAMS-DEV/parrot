import Foundation
import Testing
@testable import Parrot

struct MeetingLinkTests {
    @Test func findsCallLinksInNotes() {
        let notes = "Agenda in the doc.\nJoin with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial in: (US) +1 555-0100"
        #expect(MeetingLink.find(in: [nil, "Room 4", notes])?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(MeetingLink.find(in: ["https://us02web.zoom.us/j/8123456789?pwd=abc"]).map { MeetingLink.service(of: $0) } == "Zoom")
        #expect(MeetingLink.find(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_x"]).map { MeetingLink.service(of: $0) } == "Teams")
    }

    @Test func theFirstPlaceWins() {
        let link = MeetingLink.find(in: ["https://zoom.us/j/1", "https://meet.google.com/abc-defg-hij"])
        #expect(link?.absoluteString == "https://zoom.us/j/1")
    }

    @Test func otherLinksAreNotCalls() {
        #expect(MeetingLink.find(in: ["Docs: https://docs.google.com/document/d/1", "https://zoom.us/download", "https://meet.google.com/"]) == nil)
        #expect(MeetingLink.find(in: ["https://notmeet.google.com.evil.com/abc"]) == nil)
    }
}

struct MeetingTimingTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func meeting() -> Meeting {
        Meeting(id: "a", title: "Standup", start: start, end: start.addingTimeInterval(1800), link: URL(string: "https://meet.google.com/abc-defg-hij")!)
    }

    @Test func remindsFromTwoMinutesBeforeUntilTenAfter() {
        #expect(!Meetings.isDue(meeting(), now: start.addingTimeInterval(-121)))
        #expect(Meetings.isDue(meeting(), now: start.addingTimeInterval(-120)))
        // An event that syncs in after the start still gets a reminder.
        #expect(Meetings.isDue(meeting(), now: start.addingTimeInterval(540)))
        #expect(!Meetings.isDue(meeting(), now: start.addingTimeInterval(600)))
    }

    @Test func reminderRoundTrips() {
        #expect(Meeting(userInfo: meeting().userInfo) == meeting())
    }

    @Test func callStopsWhenTheMeetingIsOverAndQuiet() {
        let end = start.addingTimeInterval(1800)
        // Running over: still talking.
        #expect(!ParrotStore.callIsOver(scheduledEnd: end, lastHeard: end.addingTimeInterval(300), now: end.addingTimeInterval(360)))
        // Quiet for 2 minutes after the end.
        #expect(ParrotStore.callIsOver(scheduledEnd: end, lastHeard: end.addingTimeInterval(300), now: end.addingTimeInterval(420)))
        // Quiet before the end is a pause, not the end.
        #expect(!ParrotStore.callIsOver(scheduledEnd: end, lastHeard: start, now: start.addingTimeInterval(600)))
    }

    @Test func anyCallStopsAfterAQuarterHourOfQuiet() {
        #expect(!ParrotStore.callIsOver(scheduledEnd: nil, lastHeard: start, now: start.addingTimeInterval(899)))
        #expect(ParrotStore.callIsOver(scheduledEnd: nil, lastHeard: start, now: start.addingTimeInterval(900)))
    }
}
