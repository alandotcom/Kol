import Foundation

/// Geometry in global screen points, with a top-left origin.
public struct OCRRegion: Sendable {
  public let bounds: CGRect
  public let anchor: CGRect

  public init?(window: CGRect, anchor: CGRect, control: CGRect? = nil) {
    guard Self.valid(window), Self.valid(anchor), window.width > 0, window.height > 0,
          window.intersects(anchor.insetBy(dx: -1, dy: -1)) else { return nil }
    self.anchor = anchor
    let horizontal = control.flatMap { Self.valid($0) && $0.width > 0 ? $0 : nil } ?? anchor
    let width = max(900, horizontal.width + 80)
    let x = control == nil ? anchor.midX - width / 2 : horizontal.minX - 40
    bounds = CGRect(x: x, y: anchor.minY - 550, width: width, height: anchor.height + 700)
      .intersection(window)
    guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
  }

  public func pixelBounds(window: CGRect, imageSize: CGSize) -> CGRect {
    CGRect(x: (bounds.minX - window.minX) * imageSize.width / window.width,
           y: (bounds.minY - window.minY) * imageSize.height / window.height,
           width: bounds.width * imageSize.width / window.width,
           height: bounds.height * imageSize.height / window.height).integral
      .intersection(CGRect(origin: .zero, size: imageSize))
  }

  public func distance(to line: CGRect) -> CGFloat {
    let dx = max(0, max(anchor.minX - line.maxX, line.minX - anchor.maxX))
    let dy = max(0, max(anchor.minY - line.maxY, line.minY - anchor.maxY))
    return hypot(dx, dy)
  }

  public static func valid(_ rect: CGRect) -> Bool {
    [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
      && rect.width >= 0 && rect.height >= 0
  }
}
