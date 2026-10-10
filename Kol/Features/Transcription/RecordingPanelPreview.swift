#if DEBUG
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class RecordingPanelPreviewState {
  enum Phase: String, CaseIterable, Identifiable {
    case hidden = "Hidden"
    case ready = "Ready"
    case recording = "Recording"
    case transcribing = "Transcribing"
    case cleaningUp = "Cleaning up"
    case preparing = "Preparing"

    var id: Self { self }

    var status: TranscriptionIndicatorView.Status {
      switch self {
      case .hidden: .hidden
      case .ready: .optionKeyPressed
      case .recording: .recording
      case .transcribing: .transcribing
      case .cleaningUp: .postProcessing
      case .preparing: .prewarming
      }
    }
  }

  var phase: Phase = .hidden
  var forceReduceMotion = false
  var forceReduceTransparency = false
  var syntheticPower = 0.018
  var testText = ""
  var actualPanelVisible = false
  var actualPanelKey = false
  var controlsWindowKey = false
  var pendingReveal: Task<Void, Never>?

  func revealAfterDelay() {
    pendingReveal?.cancel()
    phase = .hidden
    pendingReveal = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      self?.phase = .recording
    }
  }
}

/// A debug launch mode that exercises the production panel without starting dictation.
@MainActor
final class RecordingPanelPreviewController: NSObject, NSWindowDelegate {
  private let state = RecordingPanelPreviewState()
  private var controlsWindow: NSWindow?
  private var panel: InvisibleWindow?

  func show() {
    if let controlsWindow {
      controlsWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    panel = InvisibleWindow.fromView(RecordingPanelPreviewContent(state: state))
    NotificationCenter.default.removeObserver(self)
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshWindowStatus),
      name: InvisibleWindow.visibilityNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshWindowStatus),
      name: NSWindow.didBecomeKeyNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshWindowStatus),
      name: NSWindow.didResignKeyNotification, object: nil
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Recording Panel Preview"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: RecordingPanelPreviewControls(state: state))
    window.delegate = self
    window.center()
    controlsWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func refreshWindowStatus(_: Notification) {
    // Read after the production panel has handled the visibility notification.
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.state.actualPanelVisible = self.panel?.isVisible ?? false
      self.state.actualPanelKey = self.panel?.isKeyWindow ?? false
      self.state.controlsWindowKey = self.controlsWindow?.isKeyWindow ?? false
    }
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  func windowWillClose(_: Notification) {
    state.pendingReveal?.cancel()
    state.phase = .hidden
    panel?.orderOut(nil)
    panel = nil
    controlsWindow = nil
    state.actualPanelVisible = false
    state.actualPanelKey = false
    state.controlsWindowKey = false
    NotificationCenter.default.removeObserver(self)
  }
}

private struct RecordingPanelPreviewContent: View {
  var state: RecordingPanelPreviewState

  var body: some View {
    TranscriptionIndicatorView(
      status: state.phase.status,
      meter: .init(averagePower: state.syntheticPower, peakPower: state.syntheticPower),
      forceReduceMotion: state.forceReduceMotion,
      forceReduceTransparency: state.forceReduceTransparency
    )
    .onChange(of: state.phase, initial: true) {
      NotificationCenter.default.post(
        name: InvisibleWindow.visibilityNotification,
        object: nil,
        userInfo: ["visible": state.phase != .hidden]
      )
    }
  }
}

private struct RecordingPanelPreviewControls: View {
  @Bindable var state: RecordingPanelPreviewState

  var body: some View {
    Form {
      Section("Indicator rendering") {
        TranscriptionIndicatorView(
          status: state.phase.status,
          meter: .init(averagePower: state.syntheticPower, peakPower: state.syntheticPower),
          forceReduceMotion: state.forceReduceMotion,
          forceReduceTransparency: state.forceReduceTransparency
        )
        .frame(maxWidth: .infinity, alignment: .center)
      }
      Section("Actual floating panel") {
        LabeledContent("Visible", value: state.actualPanelVisible ? "Yes" : "No")
        LabeledContent("Owns keyboard focus", value: state.actualPanelKey ? "Yes" : "No")
        LabeledContent("Controls window owns focus", value: state.controlsWindowKey ? "Yes" : "No")
      }
      Picker("Phase", selection: $state.phase) {
        ForEach(RecordingPanelPreviewState.Phase.allCases) { phase in
          Text(phase.rawValue).tag(phase)
        }
      }
      Toggle("Force Reduce Motion", isOn: $state.forceReduceMotion)
      Toggle("Force Reduce Transparency", isOn: $state.forceReduceTransparency)
      Slider(value: $state.syntheticPower, in: 0.003...0.023) {
        Text("Synthetic microphone level")
      }
      TextField("Typing focus test", text: $state.testText)
        .textFieldStyle(.roundedBorder)
      Button("Show Recording in 2 Seconds") { state.revealAfterDelay() }
      Text("Click the text field and type while the panel appears. This preview uses synthetic input and starts no recording or network requests.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .frame(width: 440, height: 540)
  }
}
#endif
