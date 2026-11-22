import Cocoa
import XCTest
@testable import Rectangle

final class WindowWriteFenceTests: XCTestCase {
    func testNewOwnerWaitsForIssuedWriteWhileUnrelatedWindowCanProceed() {
        let fence = WindowWriteFence()
        let first = target(10)
        let second = target(20)
        let release = DispatchSemaphore(value: 0)
        let drained = expectation(description: "Issued worker finished")
        let replacementReady = expectation(description: "Conflicting replacement can write")
        let independentReady = expectation(description: "Unrelated replacement can write immediately")
        var order: [String] = []

        let old = fence.claim([first])
        fence.whenReady(old) {
            fence.perform(old, work: { release.wait(timeout: .now() + 3) }) { result in
                XCTAssertEqual(result, .success)
                order.append("old worker finished")
                drained.fulfill()
            }
        }

        let replacement = fence.claim([first], isExternal: false)
        XCTAssertFalse(old.isCurrent)
        fence.whenReady(replacement) {
            order.append("replacement started")
            fence.finish(replacement)
            replacementReady.fulfill()
        }

        let unrelated = fence.claim([second], isExternal: false)
        fence.whenReady(unrelated) {
            order.append("unrelated started")
            fence.finish(unrelated)
            independentReady.fulfill()
        }
        XCTAssertEqual(order, ["unrelated started"])
        release.signal()
        wait(for: [independentReady, drained, replacementReady], timeout: 5, enforceOrder: true)
        XCTAssertEqual(order, ["unrelated started", "old worker finished", "replacement started"])
    }

    func testSupersedingEitherMemberInvalidatesPairBeforeItCanWrite() {
        let fence = WindowWriteFence()
        let memberA = target(30)
        let memberB = target(40)
        let stalled = fence.claim([memberA])
        let release = DispatchSemaphore(value: 0)
        let drained = expectation(description: "Stalled worker drained")
        fence.perform(stalled, work: { release.wait(timeout: .now() + 3) }) { _ in drained.fulfill() }

        var cancelled = false
        let pair = fence.claim([memberA, memberB]) { cancelled = true }
        fence.whenReady(pair) { XCTFail("The obsolete pair must not write either member") }
        XCTAssertTrue(fence.hasConflictingExternalWork(for: [memberB]))

        let new = fence.claim([memberB], isExternal: false)
        XCTAssertTrue(cancelled)
        XCTAssertFalse(stalled.isCurrent)
        XCTAssertFalse(pair.isCurrent)
        var replacementRan = false
        fence.whenReady(new) {
            replacementRan = true
            fence.finish(new)
        }
        XCTAssertTrue(replacementRan, "Ownership of the second member does not depend on its partner once the pair is retired")
        release.signal()
        wait(for: [drained], timeout: 5)
    }

    func testUnknownIDWaitsForDrainingExternalWork() {
        let fence = WindowWriteFence()
        let release = DispatchSemaphore(value: 0)
        let replacementReady = expectation(description: "Unknown target admitted after all possible conflicting writes")
        let old = fence.claim([target(50)])
        fence.perform(old, work: { release.wait(timeout: .now() + 3) }) { _ in }
        fence.finish(old)

        let unknown = WindowWriteFence.Target(element: nil, windowID: nil)
        let replacement = fence.claim([unknown], isExternal: false)
        var replacementRan = false
        fence.whenReady(replacement) {
            replacementRan = true
            fence.finish(replacement)
            replacementReady.fulfill()
        }
        XCTAssertFalse(replacementRan)
        release.signal()
        wait(for: [replacementReady], timeout: 5)
        XCTAssertTrue(replacementRan)
    }

    func testUnknownCommandSupersedesAnExternalOwnerBetweenWritePhases() {
        let fence = WindowWriteFence()
        var cancelled = false
        let old = fence.claim([target(70)]) { cancelled = true }
        let unknown = WindowWriteFence.Target(element: nil, windowID: nil)
        let new = fence.claim([unknown], isExternal: false)
        XCTAssertTrue(cancelled)
        XCTAssertFalse(old.isCurrent)
        XCTAssertTrue(new.isCurrent)
        fence.whenReady(old) { XCTFail("The old owner must not start another write") }
        fence.finish(new)
    }

    func testUnknownCommandSupersedesAnEarlierInternalOwner() {
        let fence = WindowWriteFence()
        let earlier = fence.claim([target(75)], isExternal: false)
        let unknown = WindowWriteFence.Target(element: nil, windowID: nil)
        let current = fence.claim([unknown], isExternal: false)
        XCTAssertFalse(earlier.isCurrent, "The resumed internal command might still own this window")
        XCTAssertTrue(current.isCurrent)
        fence.finish(current)
    }

    func testPlanningNewestFirstDoesNotInvalidateTheOldOwnerOnRejection() {
        let fence = WindowWriteFence()
        let first = target(80)
        let release = DispatchSemaphore(value: 0)
        let drained = expectation(description: "Worker and pending plans completed")
        let old = fence.claim([first])
        fence.perform(old, work: { release.wait(timeout: .now() + 3) }) { _ in
            XCTAssertFalse(old.isCurrent)
            drained.fulfill()
        }
        var order: [String] = []
        XCTAssertTrue(fence.deferPlanningIfNeeded(for: [first], discard: nil) {
            order.append("older action accepted")
            let accepted = fence.claim([first], isExternal: false)
            fence.finish(accepted)
        })
        XCTAssertTrue(fence.deferPlanningIfNeeded(for: [first], discard: nil) {
            order.append("newer action rejected")
            XCTAssertTrue(old.isCurrent, "Planning alone cannot take ownership")
        })
        release.signal()
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(order, ["newer action rejected", "older action accepted"])
    }

    func testOwnedRollbackWaitsForItsEarlierWrite() {
        let fence = WindowWriteFence()
        let lease = fence.claim([target(60)])
        let release = DispatchSemaphore(value: 0)
        let firstFinished = expectation(description: "Forward write finished")
        let rollbackReady = expectation(description: "Owner can begin rollback")
        fence.perform(lease, work: { release.wait(timeout: .now() + 3) }) { result in
            XCTAssertEqual(result, .success)
            firstFinished.fulfill()
        }

        var rollbackStarted = false
        fence.whenReady(lease) {
            XCTAssertTrue(lease.isCurrent)
            rollbackStarted = true
            fence.finish(lease)
            rollbackReady.fulfill()
        }
        XCTAssertFalse(rollbackStarted)
        release.signal()
        wait(for: [firstFinished, rollbackReady], timeout: 5, enforceOrder: true)
    }

    private func target(_ id: CGWindowID) -> WindowWriteFence.Target {
        .init(element: nil, windowID: id)
    }
}
