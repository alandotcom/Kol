import AppKit
import SwiftUI

/// A compact status panel that leaves keyboard focus in the dictation destination.
class InvisibleWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  static let visibilityNotification = Notification.Name("KolRecordingPanelVisibility")

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 248, height: 52),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .statusBar
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    hidesOnDeactivate = false
    canHide = false
    // The status display has no controls and never consumes destination clicks.
    ignoresMouseEvents = true
    collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]

    NotificationCenter.default.addObserver(
      self, selector: #selector(visibilityChanged),
      name: Self.visibilityNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenParametersChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil
    )
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  private func position(on screen: NSScreen) {
    let visibleFrame = screen.visibleFrame
    setFrameOrigin(NSPoint(
      x: visibleFrame.midX - frame.width / 2,
      y: visibleFrame.maxY - frame.height - 12
    ))
  }

  @objc private func visibilityChanged(_ notification: Notification) {
    guard let visible = notification.userInfo?["visible"] as? Bool else { return }
    if visible {
      guard !isVisible else { return }
      let destination = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        ?? NSScreen.main
      if let destination { position(on: destination) }
      orderFrontRegardless()
    } else {
      orderOut(nil)
    }
  }

  @objc private func screenParametersChanged(_: Notification) {
    guard isVisible, let destination = screen ?? NSScreen.main else { return }
    position(on: destination)
  }
}

extension InvisibleWindow {
  static func fromView<V: View>(_ view: V) -> InvisibleWindow {
    let window = InvisibleWindow()
    let hostingView = NSHostingView(rootView: view)
    window.contentView = hostingView
    let size = hostingView.fittingSize
    if size.width > 0, size.height > 0 { window.setContentSize(size) }
    return window
  }
}
