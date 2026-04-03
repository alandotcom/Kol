import Foundation

extension Date {
	private static let dayOfWeekFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "EEEE"
		return f
	}()

	private static let mediumDateFormatter: DateFormatter = {
		let f = DateFormatter()
		f.dateStyle = .medium
		f.timeStyle = .none
		return f
	}()

	func relativeFormatted() -> String {
		let calendar = Calendar.current
		let now = Date()

		if calendar.isDateInToday(self) {
			return "Today"
		} else if calendar.isDateInYesterday(self) {
			return "Yesterday"
		} else if let daysAgo = calendar.dateComponents([.day], from: self, to: now).day, daysAgo < 7 {
			return Self.dayOfWeekFormatter.string(from: self)
		} else {
			return Self.mediumDateFormatter.string(from: self)
		}
	}
}
