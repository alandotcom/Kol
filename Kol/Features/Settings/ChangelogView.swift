import SwiftUI
import Inject
import MarkdownUI

struct ChangelogView: View {
    @ObserveInjection var inject
    @Environment(\.dismiss) var dismiss
    @State private var changelogContent: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Changelog")
                    .font(.title)
                    .padding(.bottom, 10)

                if let changelogContent {
                    Markdown(changelogContent)
                } else {
                    Text("Changelog could not be loaded.")
                        .foregroundColor(.red)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 20)
            }
            .padding()
        }
        .task {
            changelogContent = Bundle.main.path(forResource: "changelog", ofType: "md")
                .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        }
        .enableInjection()
    }
}
