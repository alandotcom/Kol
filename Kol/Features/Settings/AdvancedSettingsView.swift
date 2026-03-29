import ComposableArchitecture
import KolCore
import Inject
import SwiftUI

struct AdvancedSettingsView: View {
    @ObserveInjection var inject
    @Bindable var store: StoreOf<SettingsFeature>
    let microphonePermission: PermissionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SectionHeader(title: "Advanced", style: .settings)

            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "AI Post-Processing", style: .section)
                LLMSectionContent(store: store)
            }

            Divider()

            if microphonePermission == .granted {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Microphone", style: .section)
                    MicrophoneSectionContent(store: store)
                }
                Divider()
            }

            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Sound", style: .section)
                SoundSectionContent(store: store)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "General", style: .section)
                GeneralSectionContent(store: store)
            }
        }
        .enableInjection()
    }
}
