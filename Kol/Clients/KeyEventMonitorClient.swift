import AppKit
import ApplicationServices
import Carbon
import ComposableArchitecture
import CoreGraphics
import Dependencies
import DependenciesMacros
import Foundation
import IOKit
import IOKit.hidsystem
import os
import Sauce

private let logger = KolLog.keyEvent

struct KeyEventMonitorToken: Sendable {
  private let cancelHandler: @Sendable () -> Void

  init(cancel: @escaping @Sendable () -> Void) {
    self.cancelHandler = cancel
  }

  func cancel() {
    cancelHandler()
  }

  static let noop = KeyEventMonitorToken(cancel: {})
}

public extension KeyEvent {
  init(cgEvent: CGEvent, type: CGEventType, isFnPressed: Bool) {
    let keyCode = Int(cgEvent.getIntegerValueField(.keyboardEventKeycode))
    // Sauce.shared.key(for:) must be called on the main thread.
    // The CGEvent tap source runs on the main run loop, so the callback should
    // always be on the main thread. NEVER use DispatchQueue.main.sync here —
    // if the main thread is blocked (e.g. by an AX call), that deadlocks the
    // active event tap and freezes ALL system input.
    let key: Key?
    if cgEvent.type == .keyDown {
      if Thread.isMainThread {
        key = Sauce.shared.key(for: keyCode)
      } else {
        // Should not happen — tap source is on main run loop.
        // Fall back to nil rather than risking deadlock.
        logger.error("Event tap callback unexpectedly off main thread; skipping Sauce key lookup for keyCode \(keyCode)")
        key = nil
      }
    } else {
      key = nil
    }

    var modifiers = Modifiers.from(carbonFlags: cgEvent.flags)
    if !isFnPressed {
      modifiers = modifiers.removing(kind: .fn)
    }
    self.init(key: key, modifiers: modifiers)
  }
}

@DependencyClient
struct KeyEventMonitorClient {
  var listenForKeyPress: @Sendable () async -> AsyncThrowingStream<KeyEvent, Error> = { .never }
  var handleKeyEvent: @Sendable (@Sendable @escaping (KeyEvent) -> Bool) -> KeyEventMonitorToken = { _ in .noop }
  var handleInputEvent: @Sendable (@Sendable @escaping (InputEvent) -> Bool) -> KeyEventMonitorToken = { _ in .noop }
  var startMonitoring: @Sendable () async -> Void = {}
  var stopMonitoring: @Sendable () -> Void = {}
}

extension KeyEventMonitorClient: DependencyKey {
  static var liveValue: KeyEventMonitorClient {
    let live = KeyEventMonitorClientLive()
    return KeyEventMonitorClient(
      listenForKeyPress: {
        live.listenForKeyPress()
      },
      handleKeyEvent: { handler in
        live.handleKeyEvent(handler)
      },
      handleInputEvent: { handler in
        live.handleInputEvent(handler)
      },
      startMonitoring: {
        live.startMonitoring()
      },
      stopMonitoring: {
        live.stopMonitoring()
      }
    )
  }
}

extension DependencyValues {
  var keyEventMonitor: KeyEventMonitorClient {
    get { self[KeyEventMonitorClient.self] }
    set { self[KeyEventMonitorClient.self] = newValue }
  }
}

@MainActor
class KeyEventMonitorClientLive {
  nonisolated(unsafe) private var eventTapPort: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  // All mutable state below is protected by `stateLock`.
  // OSAllocatedUnfairLock is Apple's recommended replacement for os_unfair_lock
  // in Swift — an order of magnitude faster than GCD dispatch for short critical
  // sections, and safe (unlike os_unfair_lock which has value-type address issues).
  // nonisolated(unsafe) because thread safety is managed by the lock, not actor
  // isolation — these are accessed from both @MainActor and nonisolated contexts.
  private let stateLock = OSAllocatedUnfairLock()
  nonisolated(unsafe) private var continuations: [UUID: @Sendable (KeyEvent) -> Bool] = [:]
  nonisolated(unsafe) private var inputContinuations: [UUID: @Sendable (InputEvent) -> Bool] = [:]
  nonisolated(unsafe) private var wantsMonitoring = false
  nonisolated(unsafe) private var accessibilityTrusted = false
  nonisolated(unsafe) private var inputMonitoringTrusted = false
  nonisolated(unsafe) private var trustMonitorTask: Task<Void, Never>?

  // Only accessed from the event tap callback (main thread) — no lock needed.
  // nonisolated(unsafe) because the C callback accesses these via Unmanaged pointer,
  // bypassing Swift's actor isolation checks. Safe because the CGEvent tap runs on
  // the main run loop, matching this class's @MainActor isolation.
  nonisolated(unsafe) private var consecutiveTimeouts = 0

  private var isMonitoring = false
  // SAFETY: Only accessed from the event tap callback (main thread run loop).
  nonisolated(unsafe) private var isFnPressed = false
  // SAFETY: Only written once from @MainActor, read from nonisolated init path.
  nonisolated(unsafe) private var hasPromptedForAccessibilityTrust = false
  @Shared(.hotkeyPermissionState) private var hotkeyPermissionState: HotkeyPermissionState

  private let trustCheckIntervalNanoseconds: UInt64 = 2_000_000_000 // 2s

  nonisolated init() {
    logger.info("Initializing HotKeyClient with CGEvent tap.")
  }

  deinit {
    self.stopMonitoring()
  }

  nonisolated private var hasRequiredPermissions: Bool {
    stateLock.withLock { accessibilityTrusted && inputMonitoringTrusted }
  }

  nonisolated private var hasHandlers: Bool {
    stateLock.withLock { !(continuations.isEmpty && inputContinuations.isEmpty) }
  }

  nonisolated private func setMonitoringIntent(_ value: Bool) {
    stateLock.withLock { wantsMonitoring = value }
  }

  nonisolated private func desiredMonitoringState() -> Bool {
    stateLock.withLock {
      wantsMonitoring
        && accessibilityTrusted
        && inputMonitoringTrusted
        && !(continuations.isEmpty && inputContinuations.isEmpty)
    }
  }

  /// Provide a stream of key events.
  nonisolated func listenForKeyPress() -> AsyncThrowingStream<KeyEvent, Error> {
    AsyncThrowingStream { continuation in
      let uuid = UUID()

      let shouldStart: Bool = stateLock.withLock {
        continuations[uuid] = { event in
          continuation.yield(event)
          return false
        }
        return continuations.count == 1 && inputContinuations.isEmpty
      }

      if shouldStart {
        startMonitoring()
      }

      // Cleanup on cancellation
      continuation.onTermination = { [weak self] _ in
        self?.removeHandlerContinuation(uuid: uuid)
      }
    }
  }

  nonisolated private func removeHandlerContinuation(uuid: UUID) {
    let shouldStop: Bool = stateLock.withLock {
      continuations[uuid] = nil
      return continuations.isEmpty && inputContinuations.isEmpty
    }
    if shouldStop {
      stopMonitoring()
    }
  }

  nonisolated private func removeInputContinuation(uuid: UUID) {
    let shouldStop: Bool = stateLock.withLock {
      inputContinuations[uuid] = nil
      return continuations.isEmpty && inputContinuations.isEmpty
    }
    if shouldStop {
      stopMonitoring()
    }
  }

  nonisolated func startMonitoring() {
    setMonitoringIntent(true)
    startTrustMonitorIfNeeded()
    refreshTrustedFlag(promptIfUntrusted: true)
    Task { [weak self] in
      await self?.refreshMonitoringState(reason: "startMonitoring")
    }
  }
  // TODO: Handle removing the handler from the continuations on deinit/cancellation
  nonisolated func handleKeyEvent(_ handler: @Sendable @escaping (KeyEvent) -> Bool) -> KeyEventMonitorToken {
    let uuid = UUID()

    let shouldStart: Bool = stateLock.withLock {
      continuations[uuid] = handler
      return continuations.count == 1 && inputContinuations.isEmpty
    }

    if shouldStart {
      startMonitoring()
    }

    return KeyEventMonitorToken { [weak self] in
      self?.removeHandlerContinuation(uuid: uuid)
    }
  }

  nonisolated func handleInputEvent(_ handler: @Sendable @escaping (InputEvent) -> Bool) -> KeyEventMonitorToken {
    let uuid = UUID()

    let shouldStart: Bool = stateLock.withLock {
      inputContinuations[uuid] = handler
      return inputContinuations.count == 1 && continuations.isEmpty
    }

    if shouldStart {
      startMonitoring()
    }

    return KeyEventMonitorToken { [weak self] in
      self?.removeInputContinuation(uuid: uuid)
    }
  }

  nonisolated func stopMonitoring() {
    setMonitoringIntent(false)
    Task { [weak self] in
      await self?.refreshMonitoringState(reason: "stopMonitoring")
    }
    cancelTrustMonitorIfNeeded()
  }

  nonisolated private func startTrustMonitorIfNeeded() {
    stateLock.lock()
    guard trustMonitorTask == nil else {
      stateLock.unlock()
      return
    }
    trustMonitorTask = Task { [weak self] in
      await self?.watchPermissions()
    }
    stateLock.unlock()
  }

  nonisolated private func cancelTrustMonitorIfNeeded() {
    stateLock.lock()
    guard !wantsMonitoring else {
      stateLock.unlock()
      return
    }
    trustMonitorTask?.cancel()
    trustMonitorTask = nil
    stateLock.unlock()
  }

  private func watchPermissions() async {
    var last = (
      accessibility: currentAccessibilityTrust(),
      input: currentInputMonitoringTrust()
    )
    await handlePermissionChange(accessibility: last.accessibility, input: last.input, reason: "initial")

    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: trustCheckIntervalNanoseconds)
      let current = (
        accessibility: currentAccessibilityTrust(),
        input: currentInputMonitoringTrust()
      )

      if current.accessibility != last.accessibility || current.input != last.input {
        let combinedBefore = last.accessibility && last.input
        let combinedAfter = current.accessibility && current.input
        let reason: String
        if combinedAfter && !combinedBefore {
          reason = "regained"
        } else if !combinedAfter && combinedBefore {
          reason = "revoked"
        } else {
          reason = "updated"
        }
        await handlePermissionChange(accessibility: current.accessibility, input: current.input, reason: reason)
        last = current
      } else if current.accessibility && current.input {
        await ensureTapIsRunning()
      }
    }
  }

  private func handlePermissionChange(accessibility: Bool, input: Bool, reason: String) async {
    setPermissionFlags(accessibility: accessibility, input: input)
    logger.notice("Permission update: accessibility=\(accessibility), inputMonitoring=\(input), reason=\(reason)")
    if accessibility && input {
      logger.notice("Keyboard monitoring permissions granted (\(reason)).")
    } else {
      if !accessibility {
        logger.error("Accessibility permission missing (\(reason)); suspending tap.")
      }
      if !input {
        logger.error("Input Monitoring permission missing (\(reason)); waiting for approval before restarting hotkeys.")
      }
    }
    await refreshMonitoringState(reason: "trust_\(reason)")
  }

  private func ensureTapIsRunning() async {
    guard desiredMonitoringState() else { return }
    await activateTapOnMain(reason: "watchdog_keepalive")
  }

  private func refreshMonitoringState(reason: String) async {
    let shouldMonitor = desiredMonitoringState()
    if shouldMonitor {
      await activateTapOnMain(reason: reason)
    } else {
      await deactivateTapOnMain(reason: reason)
    }
  }

  nonisolated private func setPermissionFlags(accessibility: Bool, input: Bool) {
    stateLock.withLock {
      accessibilityTrusted = accessibility
      inputMonitoringTrusted = input
    }
    recordSharedPermissionState(accessibility: accessibility, input: input)
  }

  nonisolated private func recordSharedPermissionState(accessibility: Bool, input: Bool) {
    // Use a local @Shared reference to avoid accessing self's MainActor-isolated property
    @Shared(.hotkeyPermissionState) var state
    $state.withLock {
      $0.accessibility = accessibility ? .granted : .denied
      $0.inputMonitoring = input ? .granted : .denied
      $0.lastUpdated = Date()
    }
  }

  private func activateTapOnMain(reason: String) async {
    await MainActor.run {
      self.activateTapIfNeeded(reason: reason)
    }
  }

  private func deactivateTapOnMain(reason: String) async {
    await MainActor.run {
      self.deactivateTap(reason: reason)
    }
  }

  @MainActor
  private func activateTapIfNeeded(reason: String) {
    guard !isMonitoring else { return }
    guard hasHandlers else { return }

    let accessibilityTrusted = currentAccessibilityTrust()
    let inputMonitoringTrusted = currentInputMonitoringTrust()
    setPermissionFlags(accessibility: accessibilityTrusted, input: inputMonitoringTrusted)
    guard accessibilityTrusted else {
      logger.error("Cannot start key event monitoring (reason: \(reason)); accessibility permission is not granted.")
      return
    }

    if !inputMonitoringTrusted {
      logger.notice("Input Monitoring not yet granted; creating event tap will trigger permission prompt (reason: \(reason)).")
    }

    let eventMask =
      ((1 << CGEventType.keyDown.rawValue)
       | (1 << CGEventType.keyUp.rawValue)
       | (1 << CGEventType.flagsChanged.rawValue)
       | (1 << CGEventType.leftMouseDown.rawValue)
       | (1 << CGEventType.rightMouseDown.rawValue)
       | (1 << CGEventType.otherMouseDown.rawValue))

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { _, type, cgEvent, userInfo in
          guard
            let hotKeyClientLive = Unmanaged<KeyEventMonitorClientLive>
            .fromOpaque(userInfo!)
            .takeUnretainedValue() as KeyEventMonitorClientLive?
          else {
            return Unmanaged.passUnretained(cgEvent)
          }

          if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            hotKeyClientLive.handleTapDisabledEvent(type)
            return Unmanaged.passUnretained(cgEvent)
          }

          // Tap is processing events normally — reset timeout counter.
          hotKeyClientLive.consecutiveTimeouts = 0

          guard hotKeyClientLive.hasRequiredPermissions else {
            return Unmanaged.passUnretained(cgEvent)
          }

          if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            _ = hotKeyClientLive.processInputEvent(.mouseClick)
            return Unmanaged.passUnretained(cgEvent)
          }

          hotKeyClientLive.updateFnStateIfNeeded(type: type, cgEvent: cgEvent)

          let keyEvent = KeyEvent(cgEvent: cgEvent, type: type, isFnPressed: hotKeyClientLive.isFnPressed)
          let handledByKeyHandler = hotKeyClientLive.processKeyEvent(keyEvent)
          let handledByInputHandler = hotKeyClientLive.processInputEvent(.keyboard(keyEvent))

          return (handledByKeyHandler || handledByInputHandler) ? nil : Unmanaged.passUnretained(cgEvent)
        },
        userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
      )
    else {
      logger.error("Failed to create event tap (reason: \(reason)).")
      return
    }

    eventTapPort = eventTap

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    self.runLoopSource = runLoopSource

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    isMonitoring = true
    logger.info("Started monitoring key events via CGEvent tap (reason: \(reason)).")
  }

  @MainActor
  private func deactivateTap(reason: String) {
    guard isMonitoring || eventTapPort != nil else { return }

    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }

    if let eventTapPort = eventTapPort {
      CGEvent.tapEnable(tap: eventTapPort, enable: false)
      self.eventTapPort = nil
    }

    isMonitoring = false
    logger.info("Suspended key event monitoring (reason: \(reason)).")
  }

  nonisolated private func handleTapDisabledEvent(_ type: CGEventType) {
    if type == .tapDisabledByTimeout {
      consecutiveTimeouts += 1
      if consecutiveTimeouts >= 3 {
        logger.error("Event tap timed out \(self.consecutiveTimeouts) times consecutively; leaving disabled to protect system input.")
        return
      }
    } else {
      consecutiveTimeouts = 0
    }
    let reason = type == .tapDisabledByTimeout ? "timeout" : "userInput"
    logger.error("Event tap disabled by \(reason); re-enabling.")
    // The tap was disabled by macOS but the mach port is still valid.
    // Just re-enable it directly — don't go through activateTapIfNeeded,
    // which guards on !isMonitoring and would be a no-op.
    if let port = eventTapPort {
      CGEvent.tapEnable(tap: port, enable: true)
    }
  }

  nonisolated private func processKeyEvent(_ keyEvent: KeyEvent) -> Bool {
    let handlerList: [@Sendable (KeyEvent) -> Bool]
    stateLock.lock()
    handlerList = Array(continuations.values)
    stateLock.unlock()
    return handlerList.reduce(false) { handled, handler in
      handler(keyEvent) || handled
    }
  }

  nonisolated private func processInputEvent(_ inputEvent: InputEvent) -> Bool {
    let handlerList: [@Sendable (InputEvent) -> Bool]
    stateLock.lock()
    handlerList = Array(inputContinuations.values)
    stateLock.unlock()
    return handlerList.reduce(false) { handled, handler in
      handler(inputEvent) || handled
    }
  }
}

extension KeyEventMonitorClientLive {
  nonisolated private func updateFnStateIfNeeded(type: CGEventType, cgEvent: CGEvent) {
    guard type == .flagsChanged else { return }
    let keyCode = Int(cgEvent.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == kVK_Function else { return }
    isFnPressed = cgEvent.flags.contains(.maskSecondaryFn)
  }

  nonisolated private func refreshTrustedFlag(promptIfUntrusted: Bool) {
    var accessibilityTrusted = currentAccessibilityTrust()
    if !accessibilityTrusted && promptIfUntrusted && !hasPromptedForAccessibilityTrust {
      accessibilityTrusted = requestAccessibilityTrustPrompt()
      hasPromptedForAccessibilityTrust = true
      logger.notice("Prompted for accessibility trust")
    }

    let inputMonitoringTrusted = currentInputMonitoringTrust()
    setPermissionFlags(accessibility: accessibilityTrusted, input: inputMonitoringTrusted)
  }

  nonisolated private func currentAccessibilityTrust() -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([promptKey: false] as CFDictionary)
  }

  nonisolated private func requestAccessibilityTrustPrompt() -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
  }

  nonisolated private func currentInputMonitoringTrust() -> Bool {
    IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
  }

  // Intentionally no request helper: creating the event tap prompts macOS 15+ for Input Monitoring
  // the same way older versions did, while we still track status for UI.
}
