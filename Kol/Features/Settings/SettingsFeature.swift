import AppKit
import AVFoundation
import ComposableArchitecture
import CoreAudio
import Dependencies
import IdentifiedCollections
import KolCore
import Sauce
import ServiceManagement

private let settingsLogger = KolLog.settings
private typealias SettingsAudioPropertyListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

private enum HotKeyCaptureTarget {
  case recording
  case pasteLastTranscript
}

// MARK: - Settings Feature

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State {
    @Shared(.kolSettings) var kolSettings: KolSettings
    @Shared(.isSettingHotKey) var isSettingHotKey: Bool = false
    @Shared(.isSettingPasteLastTranscriptHotkey) var isSettingPasteLastTranscriptHotkey: Bool = false
    @Shared(.isRemappingScratchpadFocused) var isRemappingScratchpadFocused: Bool = false
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
    @Shared(.hotkeyPermissionState) var hotkeyPermissionState: HotkeyPermissionState

    var languages: IdentifiedArrayOf<Language> = []
    var currentModifiers: Modifiers = .init(modifiers: [])
    var currentPasteLastModifiers: Modifiers = .init(modifiers: [])
    var remappingScratchpadText: String = ""
    
    // Available microphones
    var availableInputDevices: [AudioInputDevice] = []
    var defaultInputDeviceName: String?

    // Model Management
    var modelDownload = ModelDownloadFeature.State()
    var shouldFlashModelSection = false

    // LLM Post-Processing
    var llmApiKey: String = ""
    var isLLMApiKeyLoaded: Bool = false
    var llmApiKeyLoadGeneration: UInt64 = 0
    var showingPromptCustomization: Bool = false
    var openRouterModels = OpenRouterModelsFeature.State()
    var showingOpenRouterModels = false
    /// Download of the on-device cleanup model: nil when idle, a fraction from 0 to 1 while downloading.
    var localCleanupDownloadProgress: Double?
    var localCleanupDownloadError: String?

    /// Preview of scratchpad text after applying word removals and remappings.
    /// Lives here (not in the view) so the pipeline logic is testable.
    var scratchpadPreviewText: String {
      var output = remappingScratchpadText
      if kolSettings.removeFillerWords {
        output = FillerWordCleanup.apply(output)
      }
      if kolSettings.wordRemovalsEnabled {
        output = WordRemovalApplier.apply(output, removals: kolSettings.wordRemovals)
      }
      output = WordRemappingApplier.apply(output, remappings: kolSettings.wordRemappings)
      return output
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)

    // Existing
    case task
    case cancelShortcutCapture
    case startSettingHotKey
    case startSettingPasteLastTranscriptHotkey
    case clearPasteLastTranscriptHotkey
    case keyEvent(KeyEvent)
    case toggleOpenOnLogin(Bool)
    case toggleShowDockIcon(Bool)
    case togglePreventSystemSleep(Bool)
    case setRecordingAudioBehavior(RecordingAudioBehavior)
    case toggleSuperFastMode(Bool)
    case setUseClipboardPaste(Bool)
    case setCopyToClipboard(Bool)
    case setDoubleTapLockEnabled(Bool)
    case setUseDoubleTapOnly(Bool)
    case setMinimumKeyTime(Double)
    case setOutputLanguage(String?)
    case setSelectedMicrophoneID(String?)
    case setVADSilenceDetection(Bool)

    // Permission delegation (forwarded to AppFeature)
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring

    // Microphone selection
    case loadAvailableInputDevices
    case availableInputDevicesLoaded([AudioInputDevice], String?)

    // Model Management
    case modelDownload(ModelDownloadFeature.Action)
    
    // History Management
    case toggleSaveTranscriptionHistory(Bool)
    case setMaxHistoryEntries(Int?)

    // Modifier configuration
    case setModifierSide(Modifier.Kind, Modifier.Side)

    // Word remappings
    case setAppendSpaceAfterDictation(Bool)
    case setRemoveFillerWords(Bool)
    case setWordRemovalsEnabled(Bool)
    case addWordRemoval
    case updateWordRemoval(WordRemoval)
    case removeWordRemoval(UUID)
    case addWordRemapping
    case updateWordRemapping(WordRemapping)
    case removeWordRemapping(UUID)
    case setRemappingScratchpadFocused(Bool)

    // LLM Post-Processing
    case setLLMEnabled(Bool)
    case setLLMPreset(String)
    case downloadLocalCleanupModel
    case localCleanupDownloadProgressed(Double)
    case localCleanupDownloadFinished(String?)
    case showOpenRouterModels
    case dismissOpenRouterModels
    case openRouterModels(OpenRouterModelsFeature.Action)
    case setLLMBaseURL(String)
    case setLLMModelName(String)
    case setLLMCustomRules(String)
    case setLLMApiKey(String)
    case loadLLMApiKey
    case llmApiKeyLoaded(preset: String, generation: UInt64, key: String?)
    case setLLMScreenContextEnabled(Bool)
    case setConversationContextEnabled(Bool)
    case setAtMentionInsertionEnabled(Bool)
    case setSlackDirectMentionsEnabled(Bool)
    case setOCRContextEnabled(Bool)
    case openScreenRecordingSettings
    case setLLMPromptCode(String?)
    case setLLMPromptMessaging(String?)
    case setLLMPromptDocument(String?)
    case setLLMPromptEmail(String?)
    case showPromptCustomization
    case dismissPromptCustomization
  }

  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.continuousClock) var clock
  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.permissions) var permissions
  @Dependency(\.transcriptPersistence) var transcriptPersistence
  @Dependency(\.keychain) var keychain
  @Dependency(\.localCleanup) var localCleanup

  private func beginCapture(_ target: HotKeyCaptureTarget, state: inout State) {
    endCapture(.recording, state: &state)
    endCapture(.pasteLastTranscript, state: &state)
    switch target {
    case .recording:
      state.$isSettingHotKey.withLock { $0 = true }
      state.currentModifiers = .init(modifiers: [])
    case .pasteLastTranscript:
      state.$isSettingPasteLastTranscriptHotkey.withLock { $0 = true }
      state.currentPasteLastModifiers = .init(modifiers: [])
    }
  }

  private func endCapture(_ target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case .recording:
      state.$isSettingHotKey.withLock { $0 = false }
      state.currentModifiers = .init(modifiers: [])
    case .pasteLastTranscript:
      state.$isSettingPasteLastTranscriptHotkey.withLock { $0 = false }
      state.currentPasteLastModifiers = .init(modifiers: [])
    }
  }

  private func captureModifiers(for target: HotKeyCaptureTarget, state: State) -> Modifiers {
    switch target {
    case .recording:
      state.currentModifiers
    case .pasteLastTranscript:
      state.currentPasteLastModifiers
    }
  }

  private func updateCaptureModifiers(_ modifiers: Modifiers, for target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case .recording:
      state.currentModifiers = modifiers
    case .pasteLastTranscript:
      state.currentPasteLastModifiers = modifiers
    }
  }

  private func applyCapturedHotKey(key: Key?, modifiers: Modifiers, for target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case .recording:
      state.$kolSettings.withLock {
        $0.hotkey.key = key
        $0.hotkey.modifiers = modifiers.erasingSides()
      }
    case .pasteLastTranscript:
      guard let key else { return }
      state.$kolSettings.withLock {
        $0.pasteLastTranscriptHotkey = HotKey(key: key, modifiers: modifiers.erasingSides())
      }
    }
  }

  private func handleCapture(_ keyEvent: KeyEvent, for target: HotKeyCaptureTarget, state: inout State) -> Effect<Action> {
    if keyEvent.key == .escape {
      endCapture(target, state: &state)
      return .none
    }

    let updatedModifiers = keyEvent.modifiers.union(captureModifiers(for: target, state: state))
    updateCaptureModifiers(updatedModifiers, for: target, state: &state)

    if target == .pasteLastTranscript, keyEvent.key != nil, updatedModifiers.isEmpty {
      return .none
    }

    if let key = keyEvent.key {
      applyCapturedHotKey(key: key, modifiers: updatedModifiers, for: target, state: &state)
      endCapture(target, state: &state)
      return .none
    }

    if target == .recording, keyEvent.modifiers.isEmpty {
      applyCapturedHotKey(key: nil, modifiers: updatedModifiers, for: target, state: &state)
      endCapture(target, state: &state)
    }

    return .none
  }

  var body: some ReducerOf<Self> {
    BindingReducer()

    Scope(state: \.modelDownload, action: \.modelDownload) {
      ModelDownloadFeature()
    }

    Scope(state: \.openRouterModels, action: \.openRouterModels) {
      OpenRouterModelsFeature()
    }

    Reduce { state, action in
      switch action {
      case .binding:
        let didNormalizeDoubleTapOnly = !state.kolSettings.doubleTapLockEnabled && state.kolSettings.useDoubleTapOnly
        if didNormalizeDoubleTapOnly {
          state.$kolSettings.withLock {
            $0.useDoubleTapOnly = false
          }
        }

        return .none

      case .task:
        if let url = Bundle.main.url(forResource: "languages", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let languages = try? JSONDecoder().decode([Language].self, from: data)
        {
          state.languages = IdentifiedArray(uniqueElements: languages)
        } else {
          settingsLogger.error("Failed to load languages JSON from bundle")
        }

        // Listen for key events and load microphones (existing + new)
        return .run { send in
          await send(.modelDownload(.fetchModels))
          await send(.loadAvailableInputDevices)
          await send(.loadLLMApiKey)

          // Listen for device connection/disconnection notifications
          // Using a simpler debounced approach with a single task
          var deviceUpdateTask: Task<Void, Never>?
          var audioHardwareObservers: [(AudioObjectPropertySelector, SettingsAudioPropertyListenerBlock)] = []

          // Helper function to debounce device updates
          func debounceDeviceUpdate() {
            deviceUpdateTask?.cancel()
            deviceUpdateTask = Task {
              try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
              if !Task.isCancelled {
                await send(.loadAvailableInputDevices)
              }
            }
          }

          func installAudioHardwareObserver(_ selector: AudioObjectPropertySelector) {
            let listener: SettingsAudioPropertyListenerBlock = { _, _ in
              debounceDeviceUpdate()
            }
            var address = audioPropertyAddress(selector)
            let status = AudioObjectAddPropertyListenerBlock(
              AudioObjectID(kAudioObjectSystemObject),
              &address,
              DispatchQueue.main,
              listener
            )

            if status == noErr {
              audioHardwareObservers.append((selector, listener))
            } else {
              settingsLogger.error("Failed to observe audio hardware selector \(selector): \(status)")
            }
          }

          let deviceConnectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AVCaptureDeviceWasConnected"),
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }
          
          let deviceDisconnectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AVCaptureDeviceWasDisconnected"),
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          let appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          installAudioHardwareObserver(kAudioHardwarePropertyDefaultInputDevice)
          installAudioHardwareObserver(kAudioHardwarePropertyDevices)

          // Be sure to clean up resources when the task is finished
          defer {
            deviceUpdateTask?.cancel()
            NotificationCenter.default.removeObserver(deviceConnectionObserver)
            NotificationCenter.default.removeObserver(deviceDisconnectionObserver)
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)

            for (selector, listener) in audioHardwareObservers {
              var address = audioPropertyAddress(selector)
              let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                listener
              )
              if status != noErr {
                settingsLogger.error("Failed to remove audio hardware observer for selector \(selector): \(status)")
              }
            }
          }

          for try await keyEvent in await keyEventMonitor.listenForKeyPress() {
            await send(.keyEvent(keyEvent))
          }
        }

      case .cancelShortcutCapture:
        endCapture(.recording, state: &state)
        endCapture(.pasteLastTranscript, state: &state)
        return .none

      case .startSettingHotKey:
        beginCapture(.recording, state: &state)
        return .none

      case .addWordRemoval:
        state.$kolSettings.withLock {
          $0.wordRemovals.append(.init(pattern: ""))
        }
        return .none

      case let .updateWordRemoval(removal):
        state.$kolSettings.withLock {
          guard let index = $0.wordRemovals.firstIndex(where: { $0.id == removal.id }) else { return }
          $0.wordRemovals[index] = removal
        }
        return .none

      case let .removeWordRemoval(id):
        state.$kolSettings.withLock {
          $0.wordRemovals.removeAll { $0.id == id }
        }
        return .none

      case .addWordRemapping:
        state.$kolSettings.withLock {
          $0.wordRemappings.append(.init(match: "", replacement: ""))
        }
        return .none

      case let .updateWordRemapping(remapping):
        state.$kolSettings.withLock {
          guard let index = $0.wordRemappings.firstIndex(where: { $0.id == remapping.id }) else { return }
          $0.wordRemappings[index] = remapping
        }
        return .none

      case let .removeWordRemapping(id):
        state.$kolSettings.withLock {
          $0.wordRemappings.removeAll { $0.id == id }
        }
        return .none

      case let .setRemappingScratchpadFocused(isFocused):
        state.$isRemappingScratchpadFocused.withLock { $0 = isFocused }
        return .none

      case .startSettingPasteLastTranscriptHotkey:
        beginCapture(.pasteLastTranscript, state: &state)
        return .none
        
      case .clearPasteLastTranscriptHotkey:
        state.$kolSettings.withLock { $0.pasteLastTranscriptHotkey = nil }
        return .none

      case let .keyEvent(keyEvent):
        if state.isSettingPasteLastTranscriptHotkey {
          return handleCapture(keyEvent, for: .pasteLastTranscript, state: &state)
        }

        guard state.isSettingHotKey else { return .none }
        return handleCapture(keyEvent, for: .recording, state: &state)

      case let .toggleOpenOnLogin(enabled):
        state.$kolSettings.withLock { $0.openOnLogin = enabled }
        return .run { _ in
          if enabled {
            try? SMAppService.mainApp.register()
          } else {
            try? SMAppService.mainApp.unregister()
          }
        }

      case let .toggleShowDockIcon(enabled):
        state.$kolSettings.withLock { $0.showDockIcon = enabled }
        return .run { _ in
          await MainActor.run {
            NotificationCenter.default.post(name: .updateAppMode, object: nil)
          }
        }

      case let .togglePreventSystemSleep(enabled):
        state.$kolSettings.withLock { $0.preventSystemSleep = enabled }
        return .none

      case let .setUseClipboardPaste(enabled):
        state.$kolSettings.withLock { $0.useClipboardPaste = enabled }
        return .none

      case let .setCopyToClipboard(enabled):
        state.$kolSettings.withLock { $0.copyToClipboard = enabled }
        return .none

      case let .setRecordingAudioBehavior(behavior):
        state.$kolSettings.withLock { $0.recordingAudioBehavior = behavior }
        return .none

      case let .toggleSuperFastMode(enabled):
        state.$kolSettings.withLock { $0.superFastModeEnabled = enabled }
        return .run { _ in
          await recording.warmUpRecorder()
        }

      case let .setDoubleTapLockEnabled(enabled):
        state.$kolSettings.withLock {
          $0.doubleTapLockEnabled = enabled
          if !enabled {
            $0.useDoubleTapOnly = false
          }
        }
        return .none

      case let .setUseDoubleTapOnly(enabled):
        state.$kolSettings.withLock {
          $0.useDoubleTapOnly = enabled && $0.doubleTapLockEnabled
        }
        return .none

      case let .setMinimumKeyTime(value):
        state.$kolSettings.withLock { $0.minimumKeyTime = value }
        return .none

      case let .setOutputLanguage(language):
        state.$kolSettings.withLock { $0.outputLanguage = language }
        return .none

      case let .setSelectedMicrophoneID(deviceID):
        state.$kolSettings.withLock { $0.selectedMicrophoneID = deviceID }
        return .none

      case let .setVADSilenceDetection(enabled):
        state.$kolSettings.withLock { $0.vadSilenceDetectionEnabled = enabled }
        return .none

      // Permission requests
      case .requestMicrophone:
        settingsLogger.info("User requested microphone permission from settings")
        return .run { _ in
          _ = await permissions.requestMicrophone()
        }

      case .requestAccessibility:
        settingsLogger.info("User requested accessibility permission from settings")
        return .run { _ in
          await permissions.requestAccessibility()
        }

      case .requestInputMonitoring:
        settingsLogger.info("User requested input monitoring permission from settings")
        return .run { _ in
          _ = await permissions.requestInputMonitoring()
        }

      // Model Management
      case let .modelDownload(.selectModel(newModel)):
        // Also store it in kolSettings:
        state.$kolSettings.withLock {
          $0.selectedModel = newModel
        }
        // Then continue with the child's normal logic:
        return .none

      case .modelDownload:
        return .none
      
      // Microphone device selection
      case .loadAvailableInputDevices:
        return .run { send in
          let devices = await recording.getAvailableInputDevices()
          let defaultName = await recording.getDefaultInputDeviceName()
          await send(.availableInputDevicesLoaded(devices, defaultName))
        }
        
      case let .availableInputDevicesLoaded(devices, defaultName):
        state.availableInputDevices = devices
        state.defaultInputDeviceName = defaultName
        return .none
        
      case let .toggleSaveTranscriptionHistory(enabled):
        state.$kolSettings.withLock { $0.saveTranscriptionHistory = enabled }
        
        return .none

      case let .setMaxHistoryEntries(maxHistoryEntries):
        state.$kolSettings.withLock { $0.maxHistoryEntries = maxHistoryEntries }
        // Trim existing history if the new limit is smaller
        if let maxEntries = maxHistoryEntries, maxEntries > 0 {
          var removed: [Transcript] = []
          state.$transcriptionHistory.withLock { history in
            while history.history.count > maxEntries {
              if let t = history.history.popLast() { removed.append(t) }
            }
          }
          if !removed.isEmpty {
            let transcriptsToDelete = removed
            return .run { [transcriptPersistence] _ in
              for transcript in transcriptsToDelete {
                try? await transcriptPersistence.deleteAudio(transcript)
              }
            }
          }
        }
        return .none

      case let .setModifierSide(kind, side):
        guard state.kolSettings.hotkey.key == nil else { return .none }
        state.$kolSettings.withLock {
          $0.hotkey.modifiers = $0.hotkey.modifiers.setting(kind: kind, to: side)
        }
        return .none

      case let .setAppendSpaceAfterDictation(enabled):
        state.$kolSettings.withLock { $0.appendSpaceAfterDictation = enabled }
        return .none

      case let .setRemoveFillerWords(enabled):
        state.$kolSettings.withLock { $0.removeFillerWords = enabled }
        return .none

      case let .setWordRemovalsEnabled(enabled):
        state.$kolSettings.withLock { $0.wordRemovalsEnabled = enabled }
        return .none

      // MARK: - LLM Post-Processing

      case let .setLLMEnabled(enabled):
        state.$kolSettings.withLock { $0.llmPostProcessingEnabled = enabled }
        if enabled, state.kolSettings.llmProviderPreset == LLMProviderPreset.local.rawValue {
          return localCleanup.isModelAvailable() ? .run { [localCleanup] _ in await localCleanup.warmUp() } : .send(.downloadLocalCleanupModel)
        }
        return .none

      case .downloadLocalCleanupModel:
        guard state.localCleanupDownloadProgress == nil, !localCleanup.isModelAvailable() else { return .none }
        state.localCleanupDownloadProgress = 0
        state.localCleanupDownloadError = nil
        return .run { [localCleanup] send in
          do {
            try await localCleanup.downloadModel { fraction in
              Task { await send(.localCleanupDownloadProgressed(fraction)) }
            }
            await send(.localCleanupDownloadFinished(nil))
            await localCleanup.warmUp()
          } catch {
            await send(.localCleanupDownloadFinished(error.localizedDescription))
          }
        }

      case let .localCleanupDownloadProgressed(fraction):
        if state.localCleanupDownloadProgress != nil { state.localCleanupDownloadProgress = fraction }
        return .none

      case let .localCleanupDownloadFinished(error):
        state.localCleanupDownloadProgress = nil
        state.localCleanupDownloadError = error
        return .none

      case let .setLLMPreset(preset):
        let oldPreset = state.kolSettings.llmProviderPreset
        let currentKey = state.isLLMApiKeyLoaded ? state.llmApiKey : ""
        state.llmApiKey = ""
        state.isLLMApiKeyLoaded = false
        state.llmApiKeyLoadGeneration += 1
        let generation = state.llmApiKeyLoadGeneration
        state.$kolSettings.withLock { settings in
          settings.llmProviderPreset = preset
          if let p = LLMProviderPreset(rawValue: preset), p != .custom {
            settings.llmProviderBaseURL = p.defaultConfig.baseURL
            settings.llmModelName = p.defaultConfig.modelName
          }
        }
        if preset == LLMProviderPreset.local.rawValue {
          state.isLLMApiKeyLoaded = true
          let available = localCleanup.isModelAvailable()
          return .merge(
            .run { [keychain, localCleanup] _ in
              if !currentKey.isEmpty {
                try? await keychain.save("llmApiKey_\(oldPreset)", currentKey)
              }
              if available { await localCleanup.warmUp() }
            },
            available ? .none : .send(.downloadLocalCleanupModel)
          )
        }
        // Save current key under old provider, load key for new provider
        return .run { [keychain] send in
          if !currentKey.isEmpty {
            try? await keychain.save("llmApiKey_\(oldPreset)", currentKey)
          }
          let newKey = await keychain.loadLLMAPIKey(for: preset)
          await send(.llmApiKeyLoaded(preset: preset, generation: generation, key: newKey))
        }

      case .showOpenRouterModels:
        guard state.kolSettings.llmProviderPreset == LLMProviderPreset.openrouter.rawValue else { return .none }
        state.openRouterModels.currentModelID = state.kolSettings.llmModelName
        state.openRouterModels.highlightedModelID = state.kolSettings.llmModelName.isEmpty ? nil : state.kolSettings.llmModelName
        state.openRouterModels.search = ""
        state.showingOpenRouterModels = true
        return .send(.openRouterModels(.appeared))

      case .dismissOpenRouterModels:
        state.showingOpenRouterModels = false
        return .send(.openRouterModels(.dismissed))

      case let .openRouterModels(.delegate(.modelSelected(id))):
        guard state.showingOpenRouterModels,
              state.kolSettings.llmProviderPreset == LLMProviderPreset.openrouter.rawValue else { return .none }
        state.$kolSettings.withLock { $0.llmModelName = id }
        state.showingOpenRouterModels = false
        return .send(.openRouterModels(.dismissed))

      case .openRouterModels:
        return .none

      case let .setLLMBaseURL(url):
        state.$kolSettings.withLock { $0.llmProviderBaseURL = url }
        return .none

      case let .setLLMModelName(name):
        state.$kolSettings.withLock { $0.llmModelName = name }
        return .none

      case let .setLLMCustomRules(rules):
        state.$kolSettings.withLock { $0.llmCustomRules = rules }
        return .none

      case let .setLLMApiKey(key):
        guard state.isLLMApiKeyLoaded else { return .none }
        let preset = state.kolSettings.llmProviderPreset
        state.llmApiKey = key
        return .run { [keychain] _ in
          if key.isEmpty {
            try? await keychain.delete("llmApiKey_\(preset)")
          } else {
            try? await keychain.save("llmApiKey_\(preset)", key)
          }
        }

      case .loadLLMApiKey:
        let preset = state.kolSettings.llmProviderPreset
        state.llmApiKey = ""
        state.isLLMApiKeyLoaded = false
        state.llmApiKeyLoadGeneration += 1
        let generation = state.llmApiKeyLoadGeneration
        return .run { [keychain] send in
          let key = await keychain.loadLLMAPIKey(for: preset)
          await send(.llmApiKeyLoaded(preset: preset, generation: generation, key: key))
        }

      case let .llmApiKeyLoaded(preset, generation, key):
        guard preset == state.kolSettings.llmProviderPreset,
              generation == state.llmApiKeyLoadGeneration else { return .none }
        state.llmApiKey = key ?? ""
        state.isLLMApiKeyLoaded = true
        return .none

      case let .setLLMScreenContextEnabled(enabled):
        state.$kolSettings.withLock { $0.llmScreenContextEnabled = enabled }
        return .none

      case let .setConversationContextEnabled(enabled):
        state.$kolSettings.withLock { $0.conversationContextEnabled = enabled }
        return .none

      case let .setAtMentionInsertionEnabled(enabled):
        state.$kolSettings.withLock { $0.atMentionInsertionEnabled = enabled }
        return .none

      case let .setSlackDirectMentionsEnabled(enabled):
        state.$kolSettings.withLock { $0.slackDirectMentionsEnabled = enabled }
        return .none

      case let .setOCRContextEnabled(enabled):
        state.$kolSettings.withLock { $0.ocrContextEnabled = enabled }
        return .none

      case .openScreenRecordingSettings:
        return .run { _ in
          await permissions.openScreenRecordingSettings()
        }

      case let .setLLMPromptCode(prompt):
        state.$kolSettings.withLock { $0.llmPromptCode = prompt }
        return .none

      case let .setLLMPromptMessaging(prompt):
        state.$kolSettings.withLock { $0.llmPromptMessaging = prompt }
        return .none

      case let .setLLMPromptDocument(prompt):
        state.$kolSettings.withLock { $0.llmPromptDocument = prompt }
        return .none

      case let .setLLMPromptEmail(prompt):
        state.$kolSettings.withLock { $0.llmPromptEmail = prompt }
        return .none

      case .showPromptCustomization:
        state.showingPromptCustomization = true
        return .none

      case .dismissPromptCustomization:
        state.showingPromptCustomization = false
        return .none

      }
    }
  }
}
