//
//  HotKeyProcessorTests.swift
//  HexCoreTests
//
//  Created by Kit Langton on 1/27/25.
//

import Foundation
@testable import KolCore
import Sauce
import Testing

struct HotKeyProcessorTests {
    // MARK: - Standard HotKey (key + modifiers) Tests

    // Tests a single key press that matches the hotkey
    @Test
    func pressAndHold_startsRecordingOnHotkey_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func pressAndHold_startsRecordingOnHotkey_modifierOnly() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
            ]
        )
    }

    // Tests releasing the hotkey stops recording
    @Test
    func pressAndHold_stopsRecordingOnHotkeyRelease_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func pressAndHold_stopsRecordingOnHotkeyRelease_modifierOnly() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func pressAndHold_stopsRecordingOnHotkeyRelease_multipleModifiers() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func pressAndHold_releasingModifierBeforeKeyStillStops() throws {
        runScenario(
            hotkey: HotKey(key: .u, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.05, key: .u, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 1.5, key: .u, modifiers: [], expectedOutput: nil, expectedIsMatched: true),
                ScenarioStep(time: 1.55, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func pressAndHold_cancelsOnOtherKeyPress_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.5, key: .b, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func pressAndHold_ignoresExtraModifierAfterThreshold_modifierOnly() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.5, key: nil, modifiers: [.option, .command], expectedOutput: nil, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func pressAndHold_doesNotCancelAfterThreshold_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 1.5, key: .b, modifiers: [.command], expectedOutput: nil, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func pressAndHold_doesNotCancelAfterThreshold_modifierOnly() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 1.5, key: nil, modifiers: [.option, .command], expectedOutput: nil, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func pressAndHold_doesNotTriggerOnBackslide_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command, .shift], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.1, key: .a, modifiers: [.command], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.3, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func doubleTapLock_startsRecordingOnDoubleTap_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.15, key: nil, modifiers: [.command], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [.command], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
            ]
        )
    }

    @Test
    func doubleTapLock_startsRecordingOnDoubleTap_modifierOnly() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
            ]
        )
    }

    @Test
    func doubleTapLock_startsRecordingOnDoubleTap_multipleModifiers() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.05, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.option], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
            ]
        )
    }

    @Test
    func doubleTapLock_ignoresSlowDoubleTap_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.4, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func doubleTapLock_ignoresSlowDoubleTap_modifierOnly() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.4, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func doubleTapLock_stopsRecordingOnNextTap_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [.command], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
                ScenarioStep(time: 1.0, key: .a, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func doubleTapLock_stopsRecordingOnNextTap_modifierOnly() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
                ScenarioStep(time: 1.0, key: nil, modifiers: [.option], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func doubleTapLock_disabled_staysPressAndHold_standard() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            doubleTapLockEnabled: false,
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.15, key: nil, modifiers: [.command], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false, expectedState: .idle),
            ]
        )
    }

    @Test
    func doubleTapOnly_ignoredWhenDoubleTapLockDisabled() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            useDoubleTapOnly: true,
            doubleTapLockEnabled: false,
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.command], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    // MARK: - Edge Cases

    @Test
    func pressAndHold_stopsRecordingOnKeyPressAndStaysDirty() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: .c, modifiers: [.option], expectedOutput: .discard, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
            ]
        )
    }

    // MARK: - Fn + Arrow Regression

    @Test
    func modifierOnly_fn_triggersAfterFnPlusKeyThenFullRelease() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.fn]),
            steps: [
                ScenarioStep(time: 0.00, key: .c,  modifiers: [.fn], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.05, key: nil, modifiers: [],    expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.20, key: nil, modifiers: [.fn], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.40, key: nil, modifiers: [],    expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func modifierOnly_fn_doesNotTriggerWhenFnRemainsHeldAfterKeyRelease() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.fn]),
            steps: [
                ScenarioStep(time: 0.00, key: .c,  modifiers: [.fn], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.05, key: nil, modifiers: [.fn], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.10, key: nil, modifiers: [],    expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.25, key: nil, modifiers: [.fn], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.60, key: nil, modifiers: [],    expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func pressAndHold_staysDirtyAfterTwoSeconds() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 2.0, key: nil, modifiers: [.option, .command], expectedOutput: nil, expectedIsMatched: true),
                ScenarioStep(time: 2.1, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: true),
                ScenarioStep(time: 2.2, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func doubleTap_onlyLocksAfterSecondRelease() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true, expectedState: .pressAndHold(startTime: Date(timeIntervalSince1970: 0.2))),
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true, expectedState: .doubleTapLock),
            ]
        )
    }

    @Test
    func doubleTap_secondTapHeldTooLongBecomesHold() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 2.2, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: true),
                ScenarioStep(time: 2.3, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    // MARK: - Additional Coverage Tests

    @Test
    func escape_cancelsFromHold() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.5, key: .escape, modifiers: [], expectedOutput: .cancel, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func escape_cancelsFromLock() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.3, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: true),
                ScenarioStep(time: 1.0, key: .escape, modifiers: [], expectedOutput: .cancel, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func escape_whileHoldingHotkey_doesNotRestart() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.5, key: .escape, modifiers: [.command], expectedOutput: .cancel, expectedIsMatched: false),
                ScenarioStep(time: 0.6, key: .a, modifiers: [.command], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.7, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.8, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func modifierOnly_doesNotTriggerWithOtherKeys() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.command, .option]),
            steps: [
                ScenarioStep(time: 0.0, key: .t, modifiers: [.command, .option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.command, .option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.3, key: nil, modifiers: [.command, .option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.4, key: nil, modifiers: [], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func multipleModifiers_partialRelease() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.5, key: nil, modifiers: [.option], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func multipleModifiers_addingExtra_ignoredAfterThreshold() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.5, key: nil, modifiers: [.option, .command, .shift], expectedOutput: nil, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func keyModifier_changingModifiers_cancelsWithin1s() throws {
        runScenario(
            hotkey: HotKey(key: .a, modifiers: [.command]),
            steps: [
                ScenarioStep(time: 0.0, key: .a, modifiers: [.command], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.5, key: .a, modifiers: [.command, .shift], expectedOutput: .stopRecording, expectedIsMatched: false),
            ]
        )
    }

    @Test
    func dirtyState_blocksInputUntilFullRelease() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.option, .command], expectedOutput: .discard, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.3, key: .c, modifiers: [.option], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.4, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.5, key: nil, modifiers: [.option], expectedOutput: .startRecording, expectedIsMatched: true),
            ]
        )
    }

    @Test
    func multipleModifiers_noBackslideActivation() throws {
        runScenario(
            hotkey: HotKey(key: nil, modifiers: [.option, .command]),
            steps: [
                ScenarioStep(time: 0.0, key: nil, modifiers: [.option, .command, .shift], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.1, key: nil, modifiers: [.option, .command], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.2, key: nil, modifiers: [], expectedOutput: nil, expectedIsMatched: false),
                ScenarioStep(time: 0.3, key: nil, modifiers: [.option, .command], expectedOutput: .startRecording, expectedIsMatched: true),
            ]
        )
    }
}

struct ScenarioStep {
    let time: TimeInterval
    let key: Key?
    let modifiers: Modifiers
    let expectedOutput: HotKeyProcessor.Output?
    let expectedIsMatched: Bool?
    let expectedState: HotKeyProcessor.State?

    init(
        time: TimeInterval,
        key: Key? = nil,
        modifiers: Modifiers = [],
        expectedOutput: HotKeyProcessor.Output? = nil,
        expectedIsMatched: Bool? = nil,
        expectedState: HotKeyProcessor.State? = nil
    ) {
        self.time = time
        self.key = key
        self.modifiers = modifiers
        self.expectedOutput = expectedOutput
        self.expectedIsMatched = expectedIsMatched
        self.expectedState = expectedState
    }
}

func runScenario(
    hotkey: HotKey,
    useDoubleTapOnly: Bool = false,
    doubleTapLockEnabled: Bool = true,
    steps: [ScenarioStep]
) {
    let sortedSteps = steps.sorted { $0.time < $1.time }

    var currentTime: TimeInterval = 0

    var processor = HotKeyProcessor(
        hotkey: hotkey,
        useDoubleTapOnly: useDoubleTapOnly,
        doubleTapLockEnabled: doubleTapLockEnabled
    )
    processor.now = { Date(timeIntervalSince1970: currentTime) }

    for step in sortedSteps {
        currentTime = step.time

        let keyEvent = KeyEvent(key: step.key, modifiers: step.modifiers)
        let actualOutput = processor.process(keyEvent: keyEvent)

        if let expected = step.expectedOutput {
            #expect(
                actualOutput == expected,
                "\(step.time)s: expected output \(expected), got \(String(describing: actualOutput))"
            )
        } else {
            #expect(
                actualOutput == nil,
                "\(step.time)s: expected no output, got \(String(describing: actualOutput))"
            )
        }

        if let expMatch = step.expectedIsMatched {
            #expect(
                processor.isMatched == expMatch,
                "\(step.time)s: expected isMatched=\(expMatch), got \(processor.isMatched)"
            )
        }

        if let expState = step.expectedState {
            #expect(
                processor.state == expState,
                "\(step.time)s: expected state=\(expState), got \(processor.state)"
            )
        }
    }
}

// MARK: - Recording Decision Tests

struct RecordingDecisionTests {
    private func makeContext(
        hotkey: HotKey,
        minimumKeyTime: TimeInterval = 0.2,
        duration: TimeInterval?
    ) -> RecordingDecisionEngine.Context {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let start = duration.map { now.addingTimeInterval(-$0) }
        return RecordingDecisionEngine.Context(
            hotkey: hotkey,
            minimumKeyTime: minimumKeyTime,
            recordingStartTime: start,
            currentTime: now
        )
    }

    @Test
    func modifierOnlyShortPressIsDiscarded() {
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.command]), duration: 0.1)
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    @Test
    func printableKeyShortPressStillProceeds() {
        let ctx = makeContext(hotkey: HotKey(key: .quote, modifiers: [.command]), duration: 0.1)
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }

    @Test
    func longPressModifierOnlyProceeds() {
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.option]), duration: 0.3)
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }

    @Test
    func missingStartTimeDefaultsToShort() {
        let ctx = RecordingDecisionEngine.Context(
            hotkey: HotKey(key: nil, modifiers: [.option]),
            minimumKeyTime: 0.2,
            recordingStartTime: nil,
            currentTime: Date(timeIntervalSinceReferenceDate: 0)
        )
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    @Test
    func modifierOnly_enforcesMinimumDuration_0_3s() {
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.1, duration: 0.25)
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    @Test
    func modifierOnly_proceedsWhenAboveMinimumDuration() {
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.1, duration: 0.35)
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }

    @Test
    func modifierOnly_respectsUserPreferenceWhenHigher() {
        let ctx = makeContext(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.5, duration: 0.4)
        #expect(RecordingDecisionEngine.decide(ctx) == .discardShortRecording)
    }

    @Test
    func printableKey_doesNotEnforceModifierOnlyMinimum() {
        let ctx = makeContext(hotkey: HotKey(key: .a, modifiers: [.command]), minimumKeyTime: 0.1, duration: 0.15)
        #expect(RecordingDecisionEngine.decide(ctx) == .proceedToTranscription)
    }
}

// MARK: - Mouse Click Tests

struct MouseClickTests {
    @Test
    func mouseClick_discardsQuickModifierOnlyRecording() throws {
        var currentTime: TimeInterval = 0
        var processor = HotKeyProcessor(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.15)
        processor.now = { Date(timeIntervalSince1970: currentTime) }

        let startOutput = processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option]))
        #expect(startOutput == .startRecording)

        currentTime = 0.25
        let clickOutput = processor.processMouseClick()
        #expect(clickOutput == .discard)
    }

    @Test
    func mouseClick_ignoredAfterThreshold() throws {
        var currentTime: TimeInterval = 0
        var processor = HotKeyProcessor(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.15)
        processor.now = { Date(timeIntervalSince1970: currentTime) }

        let startOutput = processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option]))
        #expect(startOutput == .startRecording)

        currentTime = 0.35
        let clickOutput = processor.processMouseClick()
        #expect(clickOutput == nil)
    }

    @Test
    func mouseClick_ignoredInDoubleTapLock() throws {
        var currentTime: TimeInterval = 0
        var processor = HotKeyProcessor(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.15)
        processor.now = { Date(timeIntervalSince1970: currentTime) }

        _ = processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option]))
        currentTime = 0.2
        _ = processor.process(keyEvent: KeyEvent(key: nil, modifiers: []))

        currentTime = 0.4
        _ = processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option]))
        currentTime = 0.5
        _ = processor.process(keyEvent: KeyEvent(key: nil, modifiers: []))

        #expect(processor.state == .doubleTapLock)

        currentTime = 0.6
        let clickOutput = processor.processMouseClick()
        #expect(clickOutput == nil)
    }

    @Test
    func mouseClick_ignoresKeyPlusModifierHotkey() throws {
        var currentTime: TimeInterval = 0
        var processor = HotKeyProcessor(hotkey: HotKey(key: .a, modifiers: [.command]), minimumKeyTime: 0.15)
        processor.now = { Date(timeIntervalSince1970: currentTime) }

        let startOutput = processor.process(keyEvent: KeyEvent(key: .a, modifiers: [.command]))
        #expect(startOutput == .startRecording)

        currentTime = 0.1
        let clickOutput = processor.processMouseClick()
        #expect(clickOutput == nil)
    }

    @Test
    func mouseClick_respectsHigherUserPreference() throws {
        var currentTime: TimeInterval = 0
        var processor = HotKeyProcessor(hotkey: HotKey(key: nil, modifiers: [.option]), minimumKeyTime: 0.5)
        processor.now = { Date(timeIntervalSince1970: currentTime) }

        let startOutput = processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.option]))
        #expect(startOutput == .startRecording)

        currentTime = 0.4
        let clickOutput = processor.processMouseClick()
        #expect(clickOutput == .discard)
    }
}
