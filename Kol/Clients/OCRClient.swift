import AppKit
import AXorcist
import Dependencies
import Foundation
import KolCore
import ScreenCaptureKit
import Vision

private let logger = KolLog.screenContext

extension OCRClient: DependencyKey {
  public static var liveValue: Self {
    Self(captureWindowVocabulary: { pid in await captureVocabulary(pid: pid) })
  }

  private struct Target: Sendable {
    let windowElement: Element
    let window: CGRect
    let anchor: CGRect
    let control: CGRect?
    let anchorKind: String
  }

  @MainActor
  private static func target(pid: pid_t) -> Target? {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          let application = Element.application(for: pid) else { return nil }
    AXUIElementSetMessagingTimeout(application.underlyingElement, 0.25)
    guard let windowElement = application.focusedWindow(),
          let window = windowElement.frame(), OCRRegion.valid(window),
          window.width > 0, window.height > 0 else { return nil }
    let focused = Element.systemWide().focusedUIElement().flatMap { element -> Element? in
      var owner: pid_t = 0
      guard AXUIElementGetPid(element.underlyingElement, &owner) == .success, owner == pid else { return nil }
      AXUIElementSetMessagingTimeout(element.underlyingElement, 0.25)
      return element
    }
    let control = focused.flatMap { element -> CGRect? in
      guard ["AXTextArea", "AXTextField", "AXComboBox"].contains(element.role() ?? ""),
            let frame = element.frame(), OCRRegion.valid(frame), frame.width > 0, frame.height > 0,
            window.intersects(frame) else { return nil }
      return frame
    }
    if let focused, let range = focused.selectedTextRange(), range.location >= 0, range.length >= 0 {
      var insertion = CFRange(location: range.location, length: 0)
      if let parameter = AXValueCreate(.cfRange, &insertion) {
        var value: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(focused.underlyingElement,
           kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
           let value, CFGetTypeID(value) == AXValueGetTypeID() {
          var rect = CGRect.zero
          if AXValueGetValue(value as! AXValue, .cgRect, &rect), OCRRegion.valid(rect), rect.height > 0,
             window.intersects(rect.insetBy(dx: -1, dy: -1)) {
            return Target(windowElement: windowElement, window: window, anchor: rect, control: control, anchorKind: "caret")
          }
        }
      }
    }
    if let control { return Target(windowElement: windowElement, window: window, anchor: control, control: control, anchorKind: "control") }
    guard let point = CGEvent(source: nil)?.location, window.contains(point) else { return nil }
    return Target(windowElement: windowElement, window: window, anchor: CGRect(origin: point, size: CGSize(width: 1, height: 1)),
                  control: nil, anchorKind: "pointer")
  }

  @MainActor
  private static func stillMatches(_ target: Target, pid: pid_t) -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
          let application = Element.application(for: pid),
          let focusedWindow = application.focusedWindow() else { return false }
    return focusedWindow == target.windowElement && focusedWindow.frame() == target.window
  }

  private static func captureVocabulary(pid: pid_t) async -> [String]? {
    let started = Date()
    guard let target = await target(pid: pid),
          let region = OCRRegion(window: target.window, anchor: target.anchor, control: target.control) else {
      logger.debug("OCR: no local anchor for active target")
      return nil
    }
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
      let windows = content.windows.filter {
        $0.owningApplication?.processID == pid && $0.windowLayer == 0
          && abs($0.frame.minX - target.window.minX) < 3 && abs($0.frame.minY - target.window.minY) < 3
          && abs($0.frame.width - target.window.width) < 3 && abs($0.frame.height - target.window.height) < 3
      }
      guard windows.count == 1, let window = windows.first, !Task.isCancelled else { return nil }
      let filter = SCContentFilter(desktopIndependentWindow: window)
      let config = SCStreamConfiguration()
      let scale = Double(filter.pointPixelScale)
      config.width = Int((window.frame.width * scale).rounded(.up))
      config.height = Int((window.frame.height * scale).rounded(.up))
      config.ignoreShadowsSingleWindow = true
      config.showsCursor = false
      let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
      guard !Task.isCancelled, await stillMatches(target, pid: pid) else { return nil }
      let pixels = region.pixelBounds(window: window.frame, imageSize: CGSize(width: image.width, height: image.height))
      guard let cropped = image.cropping(to: pixels) else { return nil }
      logger.debug("OCR: local \(target.anchorKind, privacy: .public) crop \(cropped.width)x\(cropped.height)")
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = false
      try VNImageRequestHandler(cgImage: cropped).perform([request])
      guard !Task.isCancelled, await stillMatches(target, pid: pid) else { return nil }
      let lines = (request.results ?? []).map { observation in
        let box = observation.boundingBox
        let rect = CGRect(x: region.bounds.minX + box.minX * region.bounds.width,
                          y: region.bounds.minY + (1 - box.maxY) * region.bounds.height,
                          width: box.width * region.bounds.width, height: box.height * region.bounds.height)
        return (observation.topCandidates(1).first?.string ?? "", rect)
      }.sorted {
        let a = region.distance(to: $0.1), b = region.distance(to: $1.1)
        if a != b { return a < b }
        return $0.1.minY == $1.1.minY ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY
      }
      var seen = Set<String>()
      let vocabulary = lines.flatMap { VocabularyExtractor.extract(from: $0.0).allTerms }
        .filter { seen.insert($0.lowercased()).inserted }
      logger.info("OCR: local capture produced \(vocabulary.count) terms in \(Int(Date().timeIntervalSince(started) * 1000))ms")
      return vocabulary.isEmpty ? nil : Array(vocabulary.prefix(30))
    } catch {
      logger.error("OCR: local capture failed: \(error.localizedDescription)")
      return nil
    }
  }
}
