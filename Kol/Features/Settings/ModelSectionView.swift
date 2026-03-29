import ComposableArchitecture
import Inject
import SwiftUI

struct ModelSectionContent: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	let shouldFlash: Bool

	var body: some View {
		ModelDownloadView(
			store: store.scope(state: \.modelDownload, action: \.modelDownload),
			shouldFlash: shouldFlash
		)
		.enableInjection()
	}
}
