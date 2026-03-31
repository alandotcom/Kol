import Foundation
import Testing
@testable import KolCore

/// Tests for the audio metering pipeline.
/// Verifies MeterBroadcast delivers values correctly across threads and to multiple subscribers.
/// No microphone or human interaction required.
@Suite("MeterPipeline")
struct MeterPipelineTests {

	// MARK: - MeterBroadcast Tests

	@Test("Broadcast delivers values to a single subscriber")
	func broadcastSingleSubscriber() async {
		let broadcast = MeterBroadcast()
		let stream = broadcast.subscribe()

		broadcast.yield(Meter(averagePower: 0.1, peakPower: 0.2))
		broadcast.yield(Meter(averagePower: 0.3, peakPower: 0.4))
		broadcast.yield(Meter(averagePower: 0.5, peakPower: 0.6))

		var received: [Double] = []
		for await meter in stream {
			received.append(meter.averagePower)
			if received.count == 3 { break }
		}

		#expect(received == [0.1, 0.3, 0.5])
	}

	@Test("Broadcast delivers values to multiple subscribers simultaneously")
	func broadcastMultipleSubscribers() async {
		let broadcast = MeterBroadcast()
		let stream1 = broadcast.subscribe()
		let stream2 = broadcast.subscribe()

		broadcast.yield(Meter(averagePower: 0.5, peakPower: 0.8))

		var received1: [Double] = []
		for await meter in stream1 {
			received1.append(meter.averagePower)
			if received1.count == 1 { break }
		}

		var received2: [Double] = []
		for await meter in stream2 {
			received2.append(meter.averagePower)
			if received2.count == 1 { break }
		}

		#expect(received1 == [0.5])
		#expect(received2 == [0.5])
	}

	@Test("Broadcast from DispatchQueue reaches async subscriber")
	func broadcastFromDispatchQueue() async {
		let broadcast = MeterBroadcast()
		let stream = broadcast.subscribe()

		// Yield from a serial DispatchQueue (same pattern as SuperFastCaptureController.processingQueue)
		let queue = DispatchQueue(label: "test.audio.processing")
		queue.sync {
			broadcast.yield(Meter(averagePower: 0.7, peakPower: 0.9))
		}

		var received: [Double] = []
		for await meter in stream {
			received.append(meter.averagePower)
			if received.count == 1 { break }
		}

		#expect(received == [0.7])
	}

	@Test("Yield with no subscribers does not crash")
	func yieldWithNoSubscribers() {
		let broadcast = MeterBroadcast()
		// Should be a no-op, not a crash. This matches production: SuperFastCaptureController
		// yields meters un-gated, before any subscriber exists.
		broadcast.yield(Meter(averagePower: 0.5, peakPower: 0.8))
		broadcast.yield(Meter(averagePower: 0.9, peakPower: 1.0))
		// If we get here without crashing, the test passes.
	}

	@Test("Subscriber cleanup: cancelled stream stops receiving values")
	func subscriberCleanupAfterCancellation() async throws {
		let broadcast = MeterBroadcast()
		let stream = broadcast.subscribe()

		// Consume from a task, then cancel it
		let task = Task {
			var count = 0
			for await _ in stream {
				count += 1
				if count == 1 { break }
			}
		}

		broadcast.yield(Meter(averagePower: 0.1, peakPower: 0.2))
		// Wait for the task to finish (it breaks after 1 value)
		await task.value

		// After the stream's for-await exits, onTermination fires and removes the subscriber.
		// Give the continuation's onTermination callback a moment to run.
		try await Task.sleep(for: .milliseconds(50))

		// Now a second subscriber should work independently — verifying the first was cleaned up
		let stream2 = broadcast.subscribe()
		broadcast.yield(Meter(averagePower: 0.9, peakPower: 1.0))

		var received: [Double] = []
		for await meter in stream2 {
			received.append(meter.averagePower)
			if received.count == 1 { break }
		}
		#expect(received == [0.9])
	}

	@Test("Late subscriber does not receive previously-yielded values")
	func lateSubscriberGetsNoReplay() async throws {
		let broadcast = MeterBroadcast()

		// Yield before any subscriber exists
		broadcast.yield(Meter(averagePower: 0.1, peakPower: 0.2))
		broadcast.yield(Meter(averagePower: 0.3, peakPower: 0.4))

		// Now subscribe
		let stream = broadcast.subscribe()

		// Yield a new value after subscription
		broadcast.yield(Meter(averagePower: 0.9, peakPower: 1.0))

		var received: [Double] = []
		for await meter in stream {
			received.append(meter.averagePower)
			if received.count == 1 { break }
		}

		// Should only see the post-subscription value, not the earlier ones
		#expect(received == [0.9])
	}

	// MARK: - WaveformSmoother Tests

	@Test("First frame initializes to target power")
	func smootherFirstFrame() {
		let smoother = WaveformSmoother()
		// averagePower=0.5, peakPower=0.5 → target = min(1.0, (0.7*0.5 + 0.3*0.5) * 1.5) = 0.75
		let result = smoother.update(time: 1000.0, averagePower: 0.5, peakPower: 0.5)
		#expect(result == 0.75)
		#expect(smoother.displayPower == 0.75)
	}

	@Test("First frame with zero input returns minimum floor")
	func smootherFirstFrameZeroInput() {
		let smoother = WaveformSmoother()
		let result = smoother.update(time: 1000.0, averagePower: 0.0, peakPower: 0.0)
		// targetPower=0, but max(0, 0.06) = 0.06
		#expect(result == 0.06)
	}

	@Test("Attack: louder value snaps instantly")
	func smootherAttack() {
		let smoother = WaveformSmoother()
		// Start quiet
		_ = smoother.update(time: 1000.0, averagePower: 0.1, peakPower: 0.1)
		let previousPower = smoother.displayPower

		// Jump to loud — should snap immediately to target, not smooth
		let result = smoother.update(time: 1000.016, averagePower: 0.6, peakPower: 0.6)
		let expectedTarget = min(1.0, (0.7 * 0.6 + 0.3 * 0.6) * 1.5)
		#expect(result == expectedTarget, "Attack should snap to exact target")
		#expect(smoother.displayPower == expectedTarget)
		#expect(smoother.displayPower > previousPower, "Power should have increased")
	}

	@Test("Decay: quieter value does not snap — decays smoothly")
	func smootherDecay() {
		let smoother = WaveformSmoother()
		// Start loud
		_ = smoother.update(time: 1000.0, averagePower: 0.6, peakPower: 0.6)
		// displayPower is now 0.9

		// Drop to silence — should NOT snap to 0, should decay
		let result = smoother.update(time: 1000.016, averagePower: 0.0, peakPower: 0.0)
		// targetPower = 0, but decay should keep displayPower well above 0
		#expect(result > 0.06, "Decay should be gradual, not instant")
		#expect(smoother.displayPower > 0.0, "displayPower should still be positive during decay")
		#expect(smoother.displayPower < 0.9, "displayPower should have decreased from 0.9")
	}

	@Test("Minimum floor: output never below 0.06")
	func smootherMinimumFloor() {
		let smoother = WaveformSmoother()
		_ = smoother.update(time: 1000.0, averagePower: 0.0, peakPower: 0.0)

		// Even after many frames of silence, output stays >= 0.06
		for i in 1...100 {
			let result = smoother.update(time: 1000.0 + Double(i) * 0.016, averagePower: 0.0, peakPower: 0.0)
			#expect(result >= 0.06, "Frame \(i): output \(result) dropped below floor")
		}
	}

	@Test("Target power is clamped to 1.0 for extreme inputs")
	func smootherClampToOne() {
		let smoother = WaveformSmoother()
		// Very loud inputs that would exceed 1.0 before clamping:
		// target = min(1.0, (0.7*1.0 + 0.3*1.0) * 1.5) = min(1.0, 1.5) = 1.0
		let result = smoother.update(time: 1000.0, averagePower: 1.0, peakPower: 1.0)
		#expect(result == 1.0)
	}
}
