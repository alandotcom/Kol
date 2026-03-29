import ComposableArchitecture
import Inject
import SwiftUI

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>
  @ObserveInjection var inject

  var body: some View {
    ZStack {
      // Subtle colorful gradient tint
      LinearGradient(
        colors: [
          Color.purple.opacity(0.06),
          Color.pink.opacity(0.04),
          Color.orange.opacity(0.03),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      HStack(spacing: 0) {
        SidebarView(
          activeTab: Binding(
            get: { store.activeTab },
            set: { store.send(.setActiveTab($0)) }
          ),
          modelBootstrapState: store.modelBootstrapState
        )

        // Detail content
        ScrollView {
          detailContent
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .font(.system(size: 14))
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .enableInjection()
  }

  @ViewBuilder
  private var detailContent: some View {
    switch store.state.activeTab {
    case .settings:
      SettingsView(
        store: store.scope(state: \.settings, action: \.settings),
        microphonePermission: store.microphonePermission,
        accessibilityPermission: store.accessibilityPermission,
        inputMonitoringPermission: store.inputMonitoringPermission
      )
    case .remappings:
      WordRemappingsView(store: store.scope(state: \.settings, action: \.settings))
    case .history:
      HistoryView(store: store.scope(state: \.history, action: \.history))
    case .advanced:
      AdvancedSettingsView(
        store: store.scope(state: \.settings, action: \.settings),
        microphonePermission: store.microphonePermission
      )
    case .about:
      AboutView(store: store.scope(state: \.settings, action: \.settings))
    }
  }
}
