import Foundation

/// Known Qwen3-ASR Core ML bundles that Kol supports.
public enum QwenModel: String, CaseIterable, Sendable {
	case caspiHebrew = "caspi-1.7b-coreml"
	case caspiHebrewF32 = "caspi-1.7b-coreml-f32"

	/// The identifier used throughout the app (matches the on-disk folder name).
	public var identifier: String { rawValue }

	/// Short capability label for UI copy.
	public var capabilityLabel: String { "Hebrew" }
}
