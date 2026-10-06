import Foundation
import Synchronization
import Testing
@testable import Parrot

struct MicTimeoutTests {
    @Test func returnsQuickWork() async throws {
        let value = try await withTimeout(1, on: DispatchQueue(label: "test")) { 7 } abandon: { _ in }
        #expect(value == 7)
    }

    @Test func stalledWorkThrowsAndIsAbandonedLater() async throws {
        let abandoned = Abandoned()
        let clock = ContinuousClock.now
        await #expect(throws: RecorderError.self) {
            try await withTimeout(0.2, on: DispatchQueue(label: "test")) {
                Thread.sleep(forTimeInterval: 0.6)
                return 7
            } abandon: { abandoned.set($0) }
        }
        // Gave up at the timeout, not when the work finished.
        #expect(ContinuousClock.now - clock < .milliseconds(500))
        try await Task.sleep(for: .milliseconds(700))
        #expect(abandoned.value == 7)
    }

    @Test func passesErrorsThrough() async {
        await #expect(throws: RecorderError.self) {
            try await withTimeout(1, on: DispatchQueue(label: "test")) { () throws -> Int in throw RecorderError.noMicrophone } abandon: { _ in }
        }
    }

    private final class Abandoned: Sendable {
        private let late = Mutex<Int?>(nil)
        var value: Int? { late.withLock { $0 } }
        func set(_ value: Int) { late.withLock { $0 = value } }
    }
}
