//
//  RecordingClient.swift
//  Kol
//
//  Created by Kit Langton on 1/24/25.
//

import AppKit
import AVFoundation
import ComposableArchitecture
import CoreAudio
import Dependencies
import DependenciesMacros
import Foundation

private let recordingLogger = KolLog.recording
private typealias CoreAudioPropertyListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

/// Represents an audio input device
struct AudioInputDevice: Identifiable, Equatable {
  var id: String
  var name: String
}

@DependencyClient
struct RecordingClient {
  var startRecording: @Sendable () async -> Void = {}
  var stopRecording: @Sendable () async -> URL = { URL(fileURLWithPath: "") }
  var requestMicrophoneAccess: @Sendable () async -> Bool = { false }
  var observeAudioLevel: @Sendable () async -> AsyncStream<Meter> = { AsyncStream { _ in } }
  var getAvailableInputDevices: @Sendable () async -> [AudioInputDevice] = { [] }
  var getDefaultInputDeviceName: @Sendable () async -> String? = { nil }
  var warmUpRecorder: @Sendable () async -> Void = {}
  var cleanup: @Sendable () async -> Void = {}
}

extension RecordingClient: DependencyKey {
  static var liveValue: Self {
    let live = RecordingClientLive()
    Task {
      await live.startObservingSystemChanges()
    }
    return Self(
      startRecording: { await live.startRecording() },
      stopRecording: { await live.stopRecording() },
      requestMicrophoneAccess: { await live.requestMicrophoneAccess() },
      observeAudioLevel: { await live.observeAudioLevel() },
      getAvailableInputDevices: { await live.getAvailableInputDevices() },
      getDefaultInputDeviceName: { await live.getDefaultInputDeviceName() },
      warmUpRecorder: { await live.warmUpRecorder() },
      cleanup: { await live.cleanup() }
    )
  }
}

// MARK: - RecordingClientLive Implementation

actor RecordingClientLive {
  private struct AudioHardwareObserver {
    let selector: AudioObjectPropertySelector
    let reason: String
    let listener: CoreAudioPropertyListenerBlock
  }

  private enum RecordingBackend: String {
    case captureEngine = "capture-engine"
    case recorderFallback = "recorder-fallback"
  }

  private struct ActiveRecordingSession {
    let startedAt: Date
    let mode: CaptureRecordingMode
    let backend: RecordingBackend
  }

  private var recorder: AVAudioRecorder?
  private let recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
  private var isRecorderPrimedForNextSession = false
  private var lastPrimedDeviceID: AudioDeviceID?
  private var recordingSessionID: UUID?
  private var activeRecordingSession: ActiveRecordingSession?
  private var lastRecordingEndedAt: Date?
  private var deferredCaptureRestartReason: String?
  private var environmentChangeDebounceTask: Task<Void, Never>?
  private var mediaControlTask: Task<Void, Never>?
  private let recorderSettings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: 16000.0,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false,
  ]
  private let meterBroadcast = MeterBroadcast()
  private var meterTask: Task<Void, Never>?
  private var _captureController: SuperFastCaptureController?
  private var captureController: SuperFastCaptureController {
    if let c = _captureController { return c }
    let c = SuperFastCaptureController(meterBroadcast: meterBroadcast)
    _captureController = c
    return c
  }
  private var captureControllerDeviceID: AudioDeviceID?
  private var notificationObservers: [NSObjectProtocol] = []
  private var audioHardwareObservers: [AudioHardwareObserver] = []
  private var isObservingSystemChanges = false

  @Shared(.kolSettings) var kolSettings: KolSettings

  @Dependency(\.mediaControl) var mediaControl

  // Cache to store already-processed device information
  private var deviceCache: [AudioDeviceID: (hasInput: Bool, name: String?)] = [:]
  private var lastDeviceCheck = Date(timeIntervalSince1970: 0)
  
  /// Gets all available input devices on the system
  func getAvailableInputDevices() async -> [AudioInputDevice] {
    // Reset cache if it's been more than 5 minutes since last full refresh
    let now = Date()
    if now.timeIntervalSince(lastDeviceCheck) > 300 {
      deviceCache.removeAll()
      lastDeviceCheck = now
    }
    
    // Get all available audio devices
    let devices = getAllAudioDevices()
    var inputDevices: [AudioInputDevice] = []
    
    // Filter to only input devices and convert to our model
    for device in devices {
      let hasInput: Bool
      let name: String?
      
      // Check cache first to avoid expensive Core Audio calls
      if let cached = deviceCache[device] {
        hasInput = cached.hasInput
        name = cached.name
      } else {
        hasInput = deviceHasInput(deviceID: device)
        name = hasInput ? getDeviceName(deviceID: device) : nil
        deviceCache[device] = (hasInput, name)
      }
      
      if hasInput, let deviceName = name {
        inputDevices.append(AudioInputDevice(id: String(device), name: deviceName))
      }
    }
    
    return inputDevices
  }

  /// Gets the current system default input device name
  func getDefaultInputDeviceName() async -> String? {
    guard let deviceID = getDefaultInputDevice() else { return nil }
    if let cached = deviceCache[deviceID], cached.hasInput, let name = cached.name {
      return name
    }
    let name = getDeviceName(deviceID: deviceID)
    if let name {
      deviceCache[deviceID] = (hasInput: true, name: name)
    }
    return name
  }
  
  func startObservingSystemChanges() {
    guard !isObservingSystemChanges else { return }
    isObservingSystemChanges = true

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    notificationObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { await self.enqueueCaptureEnvironmentChange(reason: "system-wake", forceRestart: true) }
      }
    )
    notificationObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.screensDidWakeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { await self.enqueueCaptureEnvironmentChange(reason: "display-wake", forceRestart: true) }
      }
    )

    let center = NotificationCenter.default
    notificationObservers.append(
      center.addObserver(
        forName: NSNotification.Name(rawValue: "AVCaptureDeviceWasConnected"),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { await self.enqueueCaptureEnvironmentChange(reason: "capture-device-connected", forceRestart: true) }
      }
    )
    notificationObservers.append(
      center.addObserver(
        forName: NSNotification.Name(rawValue: "AVCaptureDeviceWasDisconnected"),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        Task { await self.enqueueCaptureEnvironmentChange(reason: "capture-device-disconnected", forceRestart: true) }
      }
    )

    installAudioHardwareObserver(
      selector: kAudioHardwarePropertyDefaultInputDevice,
      reason: "default-input-changed"
    )
    installAudioHardwareObserver(
      selector: kAudioHardwarePropertyDefaultOutputDevice,
      reason: "default-output-changed"
    )
    installAudioHardwareObserver(
      selector: kAudioHardwarePropertyDevices,
      reason: "audio-devices-changed"
    )

    recordingLogger.notice("Installed recording environment observers")
  }

  private func installAudioHardwareObserver(
    selector: AudioObjectPropertySelector,
    reason: String
  ) {
    let listener: CoreAudioPropertyListenerBlock = { [weak self] _, _ in
      guard let self else { return }
      Task { await self.enqueueCaptureEnvironmentChange(reason: reason, forceRestart: true) }
    }

    var address = audioPropertyAddress(selector)
    let status = AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main,
      listener
    )

    if status == noErr {
      audioHardwareObservers.append(
        AudioHardwareObserver(selector: selector, reason: reason, listener: listener)
      )
    } else {
      recordingLogger.error("Failed to install audio observer reason=\(reason) status=\(status)")
    }
  }

  private func enqueueCaptureEnvironmentChange(reason: String, forceRestart: Bool) {
    environmentChangeDebounceTask?.cancel()
    environmentChangeDebounceTask = Task { [self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      await handleCaptureEnvironmentChange(reason: reason, forceRestart: forceRestart)
    }
  }

  private func stopObservingSystemChanges() {
    guard isObservingSystemChanges else { return }
    isObservingSystemChanges = false
    environmentChangeDebounceTask?.cancel()
    environmentChangeDebounceTask = nil

    for observer in notificationObservers {
      NotificationCenter.default.removeObserver(observer)
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    notificationObservers.removeAll()

    for observer in audioHardwareObservers {
      var address = audioPropertyAddress(observer.selector)
      let status = AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        DispatchQueue.main,
        observer.listener
      )
      if status != noErr {
        recordingLogger.error("Failed to remove audio observer reason=\(observer.reason) status=\(status)")
      }
    }
    audioHardwareObservers.removeAll()
  }

  private func handleCaptureEnvironmentChange(reason: String, forceRestart: Bool) async {
    let currentInputDevice = getDefaultInputDevice()
    let currentOutputDevice = getDefaultOutputDevice()
    let isRecorderRecording = recorder?.isRecording == true
    let isEngineRecording = captureController.isRecording
    let isRecordingActive = isRecorderRecording || isEngineRecording

    recordingLogger.notice(
      "Capture environment changed reason=\(reason) activeRecording=\(isRecordingActive) input=\(self.describeDevice(currentInputDevice)) output=\(self.describeDevice(currentOutputDevice)) captureEngineArmed=\(self.captureController.isRunning) primed=\(self.isRecorderPrimedForNextSession)"
    )

    if isRecordingActive {
      deferredCaptureRestartReason = reason
      invalidatePrimedState()
      recordingLogger.notice("Deferring capture restart until current recording stops reason=\(reason)")
      return
    }

    deferredCaptureRestartReason = nil
    let activeInputDevice = applyPreferredInputDevice()

    if kolSettings.superFastModeEnabled {
      releaseRecorder(reason: "environment-change-\(reason)")
      do {
        try ensureCaptureControllerReady(
          for: activeInputDevice,
          reason: reason,
          forceRestart: forceRestart
        )
      } catch {
        recordingLogger.error("Failed to restart capture engine after \(reason): \(error.localizedDescription)")
      }
      return
    }

    stopCaptureController(reason: reason)
    let shouldReprimeRecorder = recorder != nil || isRecorderPrimedForNextSession
    releaseRecorder(reason: "environment-change-\(reason)")

    guard shouldReprimeRecorder else {
      recordingLogger.debug("No warm recorder state to rebuild after reason=\(reason)")
      return
    }

    do {
      try primeRecorderForNextSession()
      recordingLogger.notice("Recorder re-primed after reason=\(reason)")
    } catch {
      recordingLogger.error("Failed to re-prime recorder after \(reason): \(error.localizedDescription)")
    }
  }

  private func flushDeferredCaptureRestartIfNeeded() async {
    guard let deferredCaptureRestartReason else { return }
    recordingLogger.notice("Applying deferred capture restart reason=\(deferredCaptureRestartReason)")
    await handleCaptureEnvironmentChange(
      reason: "deferred-\(deferredCaptureRestartReason)",
      forceRestart: true
    )
  }

  /// Get all available audio devices
  private func getAllAudioDevices() -> [AudioDeviceID] {
    var propertySize: UInt32 = 0
    var address = audioPropertyAddress(kAudioHardwarePropertyDevices)
    
    // Get the property data size
    var status = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &propertySize
    )
    
    if status != 0 {
      recordingLogger.error("AudioObjectGetPropertyDataSize failed: \(status)")
      return []
    }
    
    // Calculate device count
    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    
    // Get the device IDs
    status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &propertySize,
      &deviceIDs
    )
    
      if status != 0 {
        recordingLogger.error("AudioObjectGetPropertyData failed while listing devices: \(status)")
        return []
      }
    
    return deviceIDs
  }
  
  /// Get device name for the given device ID
  private func getDeviceName(deviceID: AudioDeviceID) -> String? {
    var address = audioPropertyAddress(kAudioDevicePropertyDeviceNameCFString)
    
    var deviceName: CFString? = nil
    var size = UInt32(MemoryLayout<CFString?>.size)
    let deviceNamePtr: UnsafeMutableRawPointer = .allocate(byteCount: Int(size), alignment: MemoryLayout<CFString?>.alignment)
    defer { deviceNamePtr.deallocate() }
    
    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      deviceNamePtr
    )
    
    if status == 0 {
        deviceName = deviceNamePtr.load(as: CFString?.self)
    }
    
      if status != 0 {
        recordingLogger.error("Failed to fetch device name: \(status)")
        return nil
      }
    
    return deviceName as String?
  }
  
  /// Check if device has input capabilities
  private func deviceHasInput(deviceID: AudioDeviceID) -> Bool {
    var address = audioPropertyAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
    
    var propertySize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(
      deviceID,
      &address,
      0,
      nil,
      &propertySize
    )
    
    if status != 0 {
      return false
    }
    
    let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
    defer { bufferList.deallocate() }
    
    let getStatus = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &propertySize,
      bufferList
    )
    
    if getStatus != 0 {
      return false
    }
    
    // Check if we have any input channels
    let buffersPointer = UnsafeMutableAudioBufferListPointer(bufferList)
    return buffersPointer.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
  }
  
  /// Set device as the default input device
  private func setInputDevice(deviceID: AudioDeviceID) {
    var device = deviceID
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = audioPropertyAddress(kAudioHardwarePropertyDefaultInputDevice)
    
    let status = AudioObjectSetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      size,
      &device
    )
    
    if status != 0 {
      recordingLogger.error("Failed to set default input device: \(status)")
    } else {
      recordingLogger.notice("Selected input device set to \(deviceID)")
    }
  }

  func requestMicrophoneAccess() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  // MARK: - Device Query

  /// Gets the current default output device ID (used for logging only)
  private func getDefaultOutputDevice() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = audioPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    return status == 0 ? deviceID : nil
  }

  /// Gets the current default input device ID
  private func getDefaultInputDevice() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = audioPropertyAddress(kAudioHardwarePropertyDefaultInputDevice)

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    if status != 0 {
      recordingLogger.error("Failed to get default input device: \(status)")
      return nil
    }

    return deviceID
  }

  private func resolvePreferredInputDevice() -> AudioDeviceID? {
    if let selectedDeviceIDString = kolSettings.selectedMicrophoneID,
       let selectedDeviceID = AudioDeviceID(selectedDeviceIDString) {
      let devices = getAllAudioDevices()
      if devices.contains(selectedDeviceID), deviceHasInput(deviceID: selectedDeviceID) {
        return selectedDeviceID
      }

      recordingLogger.notice("Selected device \(selectedDeviceID) missing; using system default")
      return nil
    }

    return nil
  }

  private func formatDuration(_ duration: TimeInterval?) -> String {
    guard let duration else { return "n/a" }
    return String(format: "%.3fs", duration)
  }

  private func describeDevice(_ deviceID: AudioDeviceID?) -> String {
    guard let deviceID else { return "none" }
    if let name = getDeviceName(deviceID: deviceID) {
      return "\(name) [\(deviceID)]"
    }
    return "unknown [\(deviceID)]"
  }

  private func logRecordingStartRequest(mode: CaptureRecordingMode, inputDeviceID: AudioDeviceID?) {
    let idleDuration = lastRecordingEndedAt.map { Date().timeIntervalSince($0) }
    let outputDeviceID = getDefaultOutputDevice()
    recordingLogger.notice(
      "Recording requested mode=\(mode.rawValue) idle=\(self.formatDuration(idleDuration)) input=\(self.describeDevice(inputDeviceID)) output=\(self.describeDevice(outputDeviceID)) fallbackPrimed=\(self.isRecorderPrimedForNextSession)"
    )
  }

  private func currentCaptureMode() -> CaptureRecordingMode {
    kolSettings.superFastModeEnabled ? .superFast : .standard
  }

  @discardableResult
  private func applyPreferredInputDevice() -> AudioDeviceID? {
    let targetDeviceID = resolvePreferredInputDevice()
    let currentDefaultDevice = getDefaultInputDevice()

    if let primedDevice = lastPrimedDeviceID, primedDevice != currentDefaultDevice {
      recordingLogger.notice("Default input changed from \(primedDevice) to \(currentDefaultDevice ?? 0); invalidating primed state")
      invalidatePrimedState()
    }

    if let targetDeviceID {
      if targetDeviceID != currentDefaultDevice {
        recordingLogger.notice("Switching input device from \(currentDefaultDevice ?? 0) to \(targetDeviceID)")
        setInputDevice(deviceID: targetDeviceID)
        invalidatePrimedState()
      } else {
        recordingLogger.debug("Device \(targetDeviceID) already set as default, skipping setInputDevice()")
      }
    } else {
      recordingLogger.debug("Using system default microphone")
    }

    return getDefaultInputDevice()
  }

  private func makeCaptureRecordingURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("kol-capture-\(UUID().uuidString).wav")
  }

  private func makeIgnoredStopURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("kol-ignored-stop-\(UUID().uuidString).wav")
  }

  nonisolated static func shouldIgnoreStopRequest(
    snapshotSessionID: UUID?,
    currentSessionID: UUID?
  ) -> Bool {
    guard let snapshotSessionID else { return false }
    return currentSessionID != snapshotSessionID
  }

  private func ensureCaptureControllerReady(
    for deviceID: AudioDeviceID?,
    reason: String,
    forceRestart: Bool = false
  ) throws {
    if forceRestart || captureControllerDeviceID != deviceID {
      recordingLogger.notice(
        "Restarting capture engine reason=\(reason) previousInput=\(self.describeDevice(self.captureControllerDeviceID)) newInput=\(self.describeDevice(deviceID)) force=\(forceRestart)"
      )
      stopCaptureController(reason: forceRestart ? "restart-\(reason)" : "input-device-changed")
    }

    try captureController.startIfNeeded(
      reason: reason,
      keepWarmBuffer: currentCaptureMode().keepsWarmBuffer
    )
    captureControllerDeviceID = deviceID
  }

  private func stopCaptureController(reason: String) {
    captureController.stop(reason: reason)
    captureControllerDeviceID = nil
  }

  private func releaseRecorder(reason: String) {
    if recorder != nil {
      recordingLogger.notice(
        "Releasing recorder reason=\(reason) primed=\(self.isRecorderPrimedForNextSession) input=\(self.describeDevice(self.lastPrimedDeviceID))"
      )
    }
    stopMeterTask()
    if recorder?.isRecording == true {
      recorder?.stop()
    }
    recorder = nil
    invalidatePrimedState()
  }

  // MARK: - Input Device Mute Detection & Fix

  /// Checks if the input device is muted at the Core Audio device level
  private func isInputDeviceMuted(_ deviceID: AudioDeviceID) -> Bool {
    var address = audioPropertyAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
    var muted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)

    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
    if status != noErr {
      // Property not supported on this device
      return false
    }
    return muted == 1
  }

  /// Unmutes the input device at the Core Audio device level
  private func unmuteInputDevice(_ deviceID: AudioDeviceID) {
    var address = audioPropertyAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
    var muted: UInt32 = 0
    let size = UInt32(MemoryLayout<UInt32>.size)

    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muted)
    if status == noErr {
      recordingLogger.warning("Input device \(deviceID) was muted at device level - automatically unmuted")
    } else {
      recordingLogger.error("Failed to unmute input device \(deviceID): \(status)")
    }
  }

  /// Checks and fixes muted input device before recording
  private func ensureInputDeviceUnmuted() {
    // Check the selected device if specified, otherwise the default
    var deviceIDsToCheck: [AudioDeviceID] = []

    if let selectedIDString = kolSettings.selectedMicrophoneID,
       let selectedID = AudioDeviceID(selectedIDString) {
      deviceIDsToCheck.append(selectedID)
    }

    if let defaultID = getDefaultInputDevice() {
      if !deviceIDsToCheck.contains(defaultID) {
        deviceIDsToCheck.append(defaultID)
      }
    }

    for deviceID in deviceIDsToCheck {
      if isInputDeviceMuted(deviceID) {
        recordingLogger.error("⚠️ Input device \(deviceID) is MUTED at Core Audio level! This causes silent recordings.")
        unmuteInputDevice(deviceID)
      }
    }
  }

  // MARK: - Recording

  func startRecording() async {
    // Check and fix device-level mute before recording
    ensureInputDeviceUnmuted()

    let sessionID = UUID()
    recordingSessionID = sessionID
    mediaControlTask?.cancel()
    mediaControlTask = nil

    // Pause/mute media in background — MediaControlClient manages its own state
    let behavior = kolSettings.recordingAudioBehavior
    if behavior != .doNothing {
      mediaControlTask = Task {
        await mediaControl.pauseForRecording(behavior)
      }
    }

    let activeInputDevice = applyPreferredInputDevice()
    let mode = currentCaptureMode()
    logRecordingStartRequest(mode: mode, inputDeviceID: activeInputDevice)
    let startRequestAt = Date()

    do {
      try ensureCaptureControllerReady(for: activeInputDevice, reason: "startRecording")
      let recordingURL = makeCaptureRecordingURL()
      try captureController.beginRecording(to: recordingURL, requestedAt: startRequestAt, mode: mode)
      let startedAt = Date()
      activeRecordingSession = ActiveRecordingSession(
        startedAt: startedAt,
        mode: mode,
        backend: .captureEngine
      )
      recordingLogger.notice(
        "Recording started mode=\(mode.rawValue) backend=\(RecordingBackend.captureEngine.rawValue) startup=\(self.formatDuration(startedAt.timeIntervalSince(startRequestAt)))"
      )
      return
    } catch {
      recordingLogger.error("Failed to start capture engine for mode=\(mode.rawValue): \(error.localizedDescription); falling back to AVAudioRecorder")
      stopCaptureController(reason: "capture-engine-start-failed")
    }

    do {
      let recorder = try ensureRecorderReadyForRecording()
      let recordCallStartedAt = Date()
      guard recorder.record() else {
        recordingLogger.error("AVAudioRecorder refused to start recording")
        endRecordingSession()
        return
      }
      let startedAt = Date()
      activeRecordingSession = ActiveRecordingSession(
        startedAt: startedAt,
        mode: mode,
        backend: .recorderFallback
      )
      startMeterTask()
      recordingLogger.notice(
        "Recording started mode=\(mode.rawValue) backend=\(RecordingBackend.recorderFallback.rawValue) recordCall=\(self.formatDuration(Date().timeIntervalSince(recordCallStartedAt))) totalStart=\(self.formatDuration(startedAt.timeIntervalSince(startRequestAt)))"
      )
    } catch {
      recordingLogger.error("Failed to start recording: \(error.localizedDescription)")
      clearActiveRecordingMetadata()
      endRecordingSession()
    }
  }

  func stopRecording() async -> URL {
    let stopSessionID = recordingSessionID
    let activeSession = activeRecordingSession

    if activeSession?.backend == .captureEngine || captureController.isRecording {
      let stopTimingEstimate = captureController.stopTimingEstimate
      recordingLogger.debug(
        "Waiting \(self.formatDuration(stopTimingEstimate.gracePeriod)) before finalizing capture-engine recording callbackInterval=\(self.formatDuration(stopTimingEstimate.callbackInterval)) bufferDuration=\(self.formatDuration(stopTimingEstimate.bufferDuration))"
      )
      try? await Task.sleep(for: .milliseconds(Int((stopTimingEstimate.gracePeriod * 1000).rounded())))

      if Self.shouldIgnoreStopRequest(
        snapshotSessionID: stopSessionID,
        currentSessionID: recordingSessionID
      ) {
        recordingLogger.notice("Ignoring stale stop request after a newer recording session started")
        return makeIgnoredStopURL()
      }
    }

    if let captureURL = captureController.finishRecording(clearBuffer: currentCaptureMode() == .superFast) {
      let stoppedAt = Date()
      let session = activeSession ?? ActiveRecordingSession(
        startedAt: stoppedAt,
        mode: currentCaptureMode(),
        backend: .captureEngine
      )
      let recordingDuration = stoppedAt.timeIntervalSince(session.startedAt)
      stopMeterTask()
      endRecordingSession()
      clearActiveRecordingMetadata()
      lastRecordingEndedAt = stoppedAt
      recordingLogger.notice(
        "Recording stopped mode=\(session.mode.rawValue) backend=\(session.backend.rawValue) duration=\(self.formatDuration(recordingDuration))"
      )

      if !kolSettings.superFastModeEnabled {
        stopCaptureController(reason: "mode-disabled-after-stop")
        releaseRecorder(reason: "capture-engine-stop")
      }

      await flushDeferredCaptureRestartIfNeeded()
      await mediaControl.resumeAfterRecording()
      return captureURL
    }

    let stoppedAt = Date()
    let session = activeSession ?? ActiveRecordingSession(
      startedAt: stoppedAt,
      mode: currentCaptureMode(),
      backend: .recorderFallback
    )
    let recordingDuration = stoppedAt.timeIntervalSince(session.startedAt)
    let wasRecording = recorder?.isRecording == true
    recorder?.stop()
    stopMeterTask()
    endRecordingSession()
    clearActiveRecordingMetadata()
    lastRecordingEndedAt = stoppedAt
    if wasRecording {
      recordingLogger.notice("Recording stopped mode=\(session.mode.rawValue) backend=\(session.backend.rawValue) duration=\(self.formatDuration(recordingDuration))")
    } else {
      recordingLogger.notice("stopRecording() called while recorder was idle")
    }

    var exportedURL = recordingURL
    var didCopyRecording = false
    do {
      exportedURL = try duplicateCurrentRecording()
      didCopyRecording = true
    } catch {
      isRecorderPrimedForNextSession = false
      recordingLogger.error("Failed to copy recording: \(error.localizedDescription)")
    }

    if didCopyRecording {
      do {
        if session.backend == .recorderFallback {
          try primeRecorderForNextSession()
        }
      } catch {
        isRecorderPrimedForNextSession = false
        recordingLogger.error("Failed to prime recorder fallback: \(error.localizedDescription)")
      }
    }

    if !kolSettings.superFastModeEnabled {
      stopCaptureController(reason: "standard-stop")
    }

    await flushDeferredCaptureRestartIfNeeded()
    await mediaControl.resumeAfterRecording()

    return exportedURL
  }

  // Actor state update helpers
  private func isCurrentSession(_ sessionID: UUID) -> Bool {
    recordingSessionID == sessionID
  }

  private func endRecordingSession() {
    recordingSessionID = nil
    mediaControlTask?.cancel()
    mediaControlTask = nil
  }

  private func clearActiveRecordingMetadata() {
    activeRecordingSession = nil
  }

  private func invalidatePrimedState() {
    isRecorderPrimedForNextSession = false
    lastPrimedDeviceID = nil
  }

  private enum RecorderPreparationError: Error {
    case failedToPrepareRecorder
    case missingRecordingOnDisk
  }

  private func ensureRecorderReadyForRecording() throws -> AVAudioRecorder {
    let recorder = try recorderOrCreate()

    if !isRecorderPrimedForNextSession {
      recordingLogger.notice("Recorder NOT primed, calling prepareToRecord() now")
      guard recorder.prepareToRecord() else {
        throw RecorderPreparationError.failedToPrepareRecorder
      }
    } else {
      recordingLogger.notice("Recorder already primed, skipping prepareToRecord()")
    }

    isRecorderPrimedForNextSession = false
    return recorder
  }

  private func recorderOrCreate() throws -> AVAudioRecorder {
    if let recorder {
      return recorder
    }

    let recorder = try AVAudioRecorder(url: recordingURL, settings: recorderSettings)
    recorder.isMeteringEnabled = true
    self.recorder = recorder
    return recorder
  }

  private func duplicateCurrentRecording() throws -> URL {
    let fm = FileManager.default

    guard fm.fileExists(atPath: recordingURL.path) else {
      throw RecorderPreparationError.missingRecordingOnDisk
    }

    let exportURL = recordingURL
      .deletingLastPathComponent()
      .appendingPathComponent("kol-recording-\(UUID().uuidString).wav")

    if fm.fileExists(atPath: exportURL.path) {
      try fm.removeItem(at: exportURL)
    }

    try fm.copyItem(at: recordingURL, to: exportURL)
    return exportURL
  }

  private func primeRecorderForNextSession() throws {
    let recorder = try recorderOrCreate()
    guard recorder.prepareToRecord() else {
      isRecorderPrimedForNextSession = false
      lastPrimedDeviceID = nil
      throw RecorderPreparationError.failedToPrepareRecorder
    }

    isRecorderPrimedForNextSession = true
    lastPrimedDeviceID = getDefaultInputDevice()
    recordingLogger.debug("Recorder primed for device \(self.lastPrimedDeviceID ?? 0)")
  }

  func startMeterTask() {
    meterTask = Task {
      while !Task.isCancelled, let r = self.recorder, r.isRecording {
        r.updateMeters()
        let averagePower = r.averagePower(forChannel: 0)
        let averageNormalized = pow(10, averagePower / 20.0)
        let peakPower = r.peakPower(forChannel: 0)
        let peakNormalized = pow(10, peakPower / 20.0)
        meterBroadcast.yield(Meter(averagePower: Double(averageNormalized), peakPower: Double(peakNormalized)))
        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }

  func stopMeterTask() {
    meterTask?.cancel()
    meterTask = nil
  }

  func observeAudioLevel() -> AsyncStream<Meter> {
    meterBroadcast.subscribe()
  }

  func warmUpRecorder() async {
    let activeInputDevice = applyPreferredInputDevice()

    if kolSettings.superFastModeEnabled {
      releaseRecorder(reason: "warm-up-super-fast")
      do {
        try ensureCaptureControllerReady(for: activeInputDevice, reason: "warmUpRecorder")
      } catch {
        recordingLogger.error("Failed to arm capture engine for super fast mode: \(error.localizedDescription)")
      }
      return
    }

    stopCaptureController(reason: "warm-up-standard")
    releaseRecorder(reason: "warm-up-standard")
    recordingLogger.debug("Standard mode uses on-demand capture engine startup; skipping idle recorder priming")
  }

  /// Release recorder resources. Call on app termination.
  func cleanup() {
    endRecordingSession()
    stopObservingSystemChanges()
    stopCaptureController(reason: "cleanup")
    releaseRecorder(reason: "cleanup")
    recordingLogger.notice("RecordingClient cleaned up")
  }
}

extension DependencyValues {
  var recording: RecordingClient {
    get { self[RecordingClient.self] }
    set { self[RecordingClient.self] = newValue }
  }
}
