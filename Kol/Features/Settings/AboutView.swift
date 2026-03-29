import ComposableArchitecture
import Inject
import SwiftUI

struct AboutView: View {
    @ObserveInjection var inject
    @Bindable var store: StoreOf<SettingsFeature>

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // App Header — centered
            VStack(spacing: 16) {
                // App icon
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .blue.opacity(0.3), radius: 12, y: 4)

                Text("Kol")
                    .font(.largeTitle.bold())

                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Up to date")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            // Features
            VStack(alignment: .leading, spacing: 12) {
                Text("Features")
                    .font(.headline)

                FeatureCard(
                    icon: "bolt.fill",
                    iconColor: .blue,
                    title: "Real-time Transcription",
                    description: "Powered by state-of-the-art speech recognition models"
                )
                FeatureCard(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "Privacy First",
                    description: "All processing happens locally on your device"
                )
                FeatureCard(
                    icon: "globe",
                    iconColor: .purple,
                    title: "Multi-language Support",
                    description: "English, Hebrew, and more languages coming soon"
                )
            }

            // Keyboard Shortcuts
            VStack(alignment: .leading, spacing: 12) {
                Text("Keyboard Shortcuts")
                    .font(.headline)

                GlassCard {
                    VStack(spacing: 0) {
                        ShortcutRow(action: "Hold to record", keys: ["⌥"])
                        Divider().background(Color.gray.opacity(0.15))
                        ShortcutRow(action: "Double-tap to lock", keys: ["⌥", "⌥"])
                        Divider().background(Color.gray.opacity(0.15))
                        ShortcutRow(action: "Open settings", keys: ["⌘", ","])
                    }
                }
            }

            // Resources
            VStack(alignment: .leading, spacing: 12) {
                Text("Resources")
                    .font(.headline)

                HStack(spacing: 12) {
                    ResourceLink(icon: "heart.fill", title: "Original Project", url: "https://github.com/kitlangton/Hex")
                    ResourceLink(icon: "envelope.fill", title: "Support", url: "https://github.com/alandotcom/Kol/issues")
                }
            }

            // Footer
            VStack(spacing: 4) {
                Text("Based on Hex by Kit Langton")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .enableInjection()
    }
}

private struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(GlassColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(GlassColors.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

private struct ShortcutRow: View {
    let action: String
    let keys: [String]

    var body: some View {
        HStack {
            Text(action)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 12)
    }
}

private struct ResourceLink: View {
    let icon: String
    let title: String
    let url: String

    @State private var isHovered = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(16)
            .background(GlassColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(GlassColors.cardBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
