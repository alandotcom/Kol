import ComposableArchitecture
import Inject
import SwiftUI

struct HistoryView: View {
	@ObserveInjection var inject
	@Environment(\.openSettings) private var openSettings
	let store: StoreOf<HistoryFeature>
	@Shared(.kolSettings) var kolSettings: KolSettings
	@State private var search = ""
	@State private var selection: UUID?
	@State private var pendingDeletion: UUID?
	@State private var showingDeleteAll = false

	private var transcripts: [Transcript] {
		store.transcriptionHistory.history.filter {
			search.isEmpty || $0.text.localizedStandardContains(search)
				|| ($0.sourceAppName?.localizedStandardContains(search) ?? false)
		}
	}

	private var selectedTranscript: Transcript? {
		return transcripts.first { $0.id == selection }
	}

	private var workspace: some View {
		NavigationSplitView {
			sidebar
				.frame(minWidth: 240)
				.navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
		} detail: {
			detail.frame(minWidth: 360)
		}
			.navigationSplitViewStyle(.balanced)
			.navigationTitle("History")
			.toolbar { historyToolbar }
	}

	private var sidebar: some View {
		List(selection: $selection) {
			if !store.transcriptionHistory.history.isEmpty {
				ForEach(transcripts) { transcript in
					HistoryRow(transcript: transcript)
						.tag(transcript.id)
						.contextMenu {
							Button("Copy Transcript", systemImage: "doc.on.doc") {
								store.send(.copyToClipboard(transcript.text))
							}
							Button(store.playingTranscriptID == transcript.id ? "Stop Audio" : "Play Audio", systemImage: store.playingTranscriptID == transcript.id ? "stop.fill" : "play.fill") {
								store.send(.playTranscript(transcript.id))
							}
							Divider()
							Button(role: .destructive) {
								pendingDeletion = transcript.id
							} label: { Label("Delete Transcript…", systemImage: "trash") }
						}
				}
			}
		}
		.searchable(text: $search, prompt: "Search transcripts")
		.safeAreaInset(edge: .bottom) {
			Text(kolSettings.saveTranscriptionHistory ? "\(transcripts.count) transcripts" : "Saving paused · \(transcripts.count) transcripts")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(12)
		}
	}

	@ViewBuilder
	private var detail: some View {
		if !kolSettings.saveTranscriptionHistory && store.transcriptionHistory.history.isEmpty {
			ContentUnavailableView {
				Label("History Disabled", systemImage: "clock.arrow.circlepath")
			} description: {
				Text("Enable transcription history in Privacy settings to save recordings and text.")
			} actions: {
				Button("Open Privacy Settings") {
					store.send(.navigateToSettings)
					openSettings()
				}
			}
		} else if let transcript = selectedTranscript {
			HistoryTranscriptDetail(transcript: transcript)
				.id(transcript.id)
		} else if store.transcriptionHistory.history.isEmpty {
			ContentUnavailableView("No Transcriptions", systemImage: "text.bubble", description: Text("Saved transcriptions will appear here after you record."))
		} else if transcripts.isEmpty {
			ContentUnavailableView.search(text: search)
		} else {
			ContentUnavailableView("Select a Transcript", systemImage: "text.alignleft", description: Text("Choose a transcript to read its text or play the recording."))
		}
	}

	@ToolbarContentBuilder
	private var historyToolbar: some ToolbarContent {
		ToolbarItemGroup {
			Button("Copy Transcript", systemImage: "doc.on.doc") {
				if let transcript = selectedTranscript { store.send(.copyToClipboard(transcript.text)) }
			}
			.keyboardShortcut("c", modifiers: [.command, .shift])
			.disabled(selectedTranscript == nil)
			.help("Copy selected transcript")
			Button(store.playingTranscriptID == selection && selection != nil ? "Stop Audio" : "Play Audio", systemImage: store.playingTranscriptID == selection && selection != nil ? "stop.fill" : "play.fill") {
				if let transcript = selectedTranscript { store.send(.playTranscript(transcript.id)) }
			}
			.disabled(selectedTranscript == nil)
			Button(role: .destructive) {
				pendingDeletion = selectedTranscript?.id
			} label: { Label("Delete Transcript…", systemImage: "trash") }
			.disabled(selectedTranscript == nil)
			Menu {
				Button("Delete All Transcripts…", role: .destructive) { showingDeleteAll = true }
					.disabled(store.transcriptionHistory.history.isEmpty)
			} label: { Label("History Actions", systemImage: "ellipsis.circle") }
		}
	}

	private var lifecycleContent: some View {
		workspace
		.onDeleteCommand { pendingDeletion = selectedTranscript?.id }
		.onChange(of: selection) { store.send(.stopPlayback) }
		.onChange(of: transcripts.map(\.id)) {
			if let selection, !transcripts.contains(where: { $0.id == selection }) {
				self.selection = nil
			}
		}
		.onDisappear { store.send(.stopPlayback) }
	}

	private var deletionAlert: some View {
		lifecycleContent
		.alert("Delete Transcript?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
			Button("Delete", role: .destructive) {
				if let id = pendingDeletion { store.send(.deleteTranscript(id)) }
				pendingDeletion = nil
			}
			Button("Cancel", role: .cancel) { pendingDeletion = nil }
		} message: { Text("The transcript and its audio recording will be permanently deleted.") }
	}

	private var deleteAllAlert: some View {
		deletionAlert
		.alert("Delete All Transcripts?", isPresented: $showingDeleteAll) {
			Button("Delete All", role: .destructive) { store.send(.confirmDeleteAll) }
			Button("Cancel", role: .cancel) {}
		} message: { Text("All saved transcripts and audio recordings will be permanently deleted.") }
	}

	var body: some View {
		deleteAllAlert
		.alert("Audio Could Not Be Played", isPresented: Binding(get: { store.playbackError != nil }, set: { if !$0 { store.send(.dismissPlaybackError) } })) {
			Button("OK") { store.send(.dismissPlaybackError) }
		} message: {
			Text(store.playbackError ?? "The recording could not be opened.")
		}
		.enableInjection()
	}
}

private struct HistoryRow: View {
	let transcript: Transcript

	private var compactTimestamp: String {
		if Calendar.current.isDateInToday(transcript.timestamp) {
			return transcript.timestamp.formatted(date: .omitted, time: .shortened)
		}
		return transcript.timestamp.formatted(.dateTime.month(.abbreviated).day())
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(transcript.text).lineLimit(2)
			HStack {
				Text(transcript.sourceAppName ?? "Dictation")
					.lineLimit(1)
					.truncationMode(.tail)
				Spacer(minLength: 8)
				Text(compactTimestamp)
					.fixedSize(horizontal: true, vertical: false)
					.help(transcript.timestamp.formatted(date: .complete, time: .shortened))
			}
			.font(.caption)
			.foregroundStyle(.secondary)
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
	}
}

private struct HistoryTranscriptDetail: View {
	let transcript: Transcript

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				VStack(alignment: .leading, spacing: 6) {
					Text(transcript.timestamp, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
						.font(.headline)
					Text("\(transcript.sourceAppName ?? "Dictation") · \(transcript.wordCount) words · \(transcript.duration.formatted(.number.precision(.fractionLength(1)))) seconds")
						.font(.subheadline).foregroundStyle(.secondary)
				}
				Text(transcript.text)
					.font(.body)
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
				if transcript.llmMetadata != nil || transcript.pipelineTiming != nil {
					Divider()
					DisclosureGroup("Processing Details") {
						VStack(alignment: .leading, spacing: 12) {
							if let metadata = transcript.llmMetadata {
								Text("Original Transcript").font(.headline)
								Text(metadata.originalText).textSelection(.enabled)
								if let model = metadata.model { LabeledContent("Model", value: model) }
								if let latency = metadata.latencyMs { LabeledContent("Processing time", value: "\(latency) ms") }
								if let tokens = metadata.promptTokens { LabeledContent("Prompt tokens", value: "\(tokens)") }
								if let tokens = metadata.completionTokens { LabeledContent("Completion tokens", value: "\(tokens)") }
							}
							if let timing = transcript.pipelineTiming {
								LabeledContent("Transcription", value: "\(timing.asrMs) ms")
								if let duration = timing.llmMs { LabeledContent("Text cleanup", value: "\(duration) ms") }
								LabeledContent("Total time", value: "\(timing.totalMs) ms")
							}
						}.font(.callout).padding(.top, 12)
					}
				}
			}
			.frame(maxWidth: 680, alignment: .leading)
			.frame(maxWidth: .infinity, alignment: .center)
			.padding(24)
		}
	}
}

#Preview("Transcript Detail") {
	HistoryTranscriptDetail(transcript: Transcript(timestamp: .now, text: "Please update the release notes and send the revised draft before Friday. The keyboard shortcuts are ready for review.", audioPath: URL(fileURLWithPath: "/tmp/kol-preview-audio.m4a"), duration: 14.2, sourceAppName: "Notes", llmMetadata: LLMMetadata(originalText: "please update the release notes and um send the revised draft before friday the keyboard shortcuts are ready for review", model: "Example model", latencyMs: 420), pipelineTiming: PipelineTiming(asrMs: 230, llmMs: 420, totalMs: 650)))
		.frame(width: 600, height: 500)
}
