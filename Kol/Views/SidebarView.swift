import SwiftUI

struct SidebarView: View {
    @Binding var activeTab: AppFeature.ActiveTab
    let modelBootstrapState: ModelBootstrapState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation
            VStack(spacing: 4) {
                ForEach(AppFeature.ActiveTab.allCases, id: \.self) { tab in
                    SidebarButton(
                        title: tab.title,
                        icon: tab.icon,
                        isSelected: activeTab == tab
                    ) {
                        activeTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()

            // Status indicator
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(statusSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 208)
        .background(Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 0.5)
        }
    }

    private var statusColor: Color {
        if modelBootstrapState.isModelReady { .green }
        else if modelBootstrapState.progress > 0 && modelBootstrapState.progress < 1 { .orange }
        else { .red }
    }

    private var statusTitle: String {
        if modelBootstrapState.isModelReady { "Active" }
        else if modelBootstrapState.progress > 0 && modelBootstrapState.progress < 1 { "Downloading..." }
        else { "Setup Required" }
    }

    private var statusSubtitle: String {
        if modelBootstrapState.isModelReady { "Model loaded and ready" }
        else if let name = modelBootstrapState.modelDisplayName { name }
        else { "No model selected" }
    }
}

private struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.12) : (isHovered ? Color.blue.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
