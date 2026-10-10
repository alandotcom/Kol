import Foundation
import Testing
@testable import KolCore

struct OCRRegionTests {
  @Test("A crop above the focused field retains nearby content on a negative-origin display")
  func cropGeometry() throws {
    let window = CGRect(x: -1600, y: 100, width: 1200, height: 900)
    let field = CGRect(x: -1300, y: 800, width: 800, height: 180)
    let region = try #require(OCRRegion(window: window, anchor: field, control: field))
    #expect(region.bounds.contains(CGPoint(x: -1100, y: 400)))
    #expect(!region.bounds.contains(CGPoint(x: -1550, y: 400)))
    let pixels = region.pixelBounds(window: window, imageSize: CGSize(width: 2400, height: 1800))
    #expect(pixels.minX == (region.bounds.minX - window.minX) * 2)
    #expect(pixels.minY == (region.bounds.minY - window.minY) * 2)
    #expect(pixels.maxY <= 1800)
    #expect(region.distance(to: CGRect(x: -1200, y: 760, width: 100, height: 20))
      < region.distance(to: CGRect(x: -1550, y: 400, width: 100, height: 20)))
  }

  @Test("An off-window or nonfinite anchor cannot define a capture")
  func invalidAnchor() {
    let window = CGRect(x: 0, y: 0, width: 1000, height: 800)
    #expect(OCRRegion(window: window, anchor: CGRect(x: 2000, y: 2000, width: 1, height: 20)) == nil)
    #expect(OCRRegion(window: window, anchor: CGRect(x: CGFloat.nan, y: 100, width: 1, height: 20)) == nil)
    #expect(OCRRegion(window: .zero, anchor: .zero) == nil)
  }
}
