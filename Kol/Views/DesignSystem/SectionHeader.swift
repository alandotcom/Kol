import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var style: Style = .page

    enum Style {
        case page      // Large page titles (Transforms, History, About)
        case settings  // Settings page title
        case section   // Subsection headings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(titleFont)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var titleFont: Font {
        switch style {
        case .page: .system(size: 20, weight: .bold)
        case .settings: .system(size: 20, weight: .semibold)
        case .section: .system(size: 16, weight: .semibold)
        }
    }
}
