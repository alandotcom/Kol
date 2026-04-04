import os.log

/// Shared helper for creating consistent os.Logger instances across the Kol app and KolCore.
///
/// Privacy: `os_log` redacts dynamic strings with `privacy: .private` by default.
/// Key diagnostic lines (raw transcription, LLM output, vocabulary hints, prompt preview)
/// use `privacy: .public` in DEBUG builds so they are visible via `log stream` without Xcode.
/// Release builds keep `.private` for all sensitive content.
public enum KolLog {
  public static let subsystem = "com.alandotcom.Kol"

  public enum Category: String {
    case app = "App"
    case caches = "Caches"
    case transcription = "Transcription"
    case models = "Models"
    case recording = "Recording"
    case media = "Media"
    case pasteboard = "Pasteboard"
    case sound = "SoundEffect"
    case hotKey = "HotKey"
    case keyEvent = "KeyEvent"
    case parakeet = "Parakeet"
    case history = "History"
    case settings = "Settings"
    case permissions = "Permissions"
    case llm = "LLM"
    case screenContext = "ScreenContext"
    case vocabulary = "Vocabulary"
    case conversation = "Conversation"
  }

  public static func logger(_ category: Category) -> os.Logger {
    os.Logger(subsystem: subsystem, category: category.rawValue)
  }

  public static let app = logger(.app)
  public static let caches = logger(.caches)
  public static let transcription = logger(.transcription)
  public static let models = logger(.models)
  public static let recording = logger(.recording)
  public static let media = logger(.media)
  public static let pasteboard = logger(.pasteboard)
  public static let sound = logger(.sound)
  public static let hotKey = logger(.hotKey)
  public static let keyEvent = logger(.keyEvent)
  public static let parakeet = logger(.parakeet)
  public static let history = logger(.history)
  public static let settings = logger(.settings)
  public static let permissions = logger(.permissions)
  public static let llm = logger(.llm)
  public static let screenContext = logger(.screenContext)
  public static let vocabulary = logger(.vocabulary)
  public static let conversation = logger(.conversation)
}
