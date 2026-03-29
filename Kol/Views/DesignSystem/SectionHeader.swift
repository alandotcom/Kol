import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var style: Style = .page

    enum Style {
        case page      // text-2xl font-bold (Transforms, History, About)
        case settings  // text-xl font-semibold (Settings)
        case section   // text-sm font-semibold (subsection headings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(titleFont)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var titleFont: Font {
        switch style {
        case .page: .title2.bold()
        case .settings: .title3.weight(.semibold)
        case .section: .subheadline.weight(.semibold)
        }
    }
}
