import Carbon
import Dependencies
import KolCore

extension InputSourceClient: DependencyKey {
	public static var liveValue: InputSourceClient {
		InputSourceClient(
			isHebrewKeyboardActive: {
				guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
				guard let idRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
				let inputSourceID = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String
				return inputSourceID.lowercased().contains("hebrew")
			}
		)
	}
}
