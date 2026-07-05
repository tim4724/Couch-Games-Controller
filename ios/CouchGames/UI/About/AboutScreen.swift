import SwiftUI

/// The About hub. Lists the legal documents (privacy notice + imprint, kept
/// plainly labeled so the Impressum stays findable). Two taps from home
/// (info icon → here → document), satisfying the "reachable from within the
/// app" requirement for the Impressum.
struct AboutScreen: View {
    let onOpenPrivacy: () -> Void
    let onOpenImprint: () -> Void

    @Environment(\.cgPalette) private var palette

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                AboutRow(label: "Privacy Policy", action: onOpenPrivacy)
                Divider()
                AboutRow(label: "Impressum", action: onOpenImprint)
                Divider()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutRow: View {
    let label: LocalizedStringKey
    let action: () -> Void

    @Environment(\.cgPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.cgBodyLarge)
                    .foregroundStyle(palette.onSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
