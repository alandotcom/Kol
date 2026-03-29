import Foundation

extension Date {
	func relativeFormatted() -> String {
		let calendar = Calendar.current
		let now = Date()

		if calendar.isDateInToday(self) {
			return "Today"
		} else if calendar.isDateInYesterday(self) {
			return "Yesterday"
		} else if let daysAgo = calendar.dateComponents([.day], from: self, to: now).day, daysAgo < 7 {
			let formatter = DateFormatter()
			formatter.dateFormat = "EEEE" // Day of week
			return formatter.string(from: self)
		} else {
			let formatter = DateFormatter()
			formatter.dateStyle = .medium
			formatter.timeStyle = .none
			return formatter.string(from: self)
		}
	}
}
