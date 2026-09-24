import SwiftUI

/// A comic cover at a fixed 2:3 aspect ratio with rounded corners and a soft shadow.
struct ComicCoverView: View {
    let comic: ComicBook
    var cornerRadius: CGFloat = 8

    @EnvironmentObject private var library: LibraryManager
    @State private var cover: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 4)
            .task(id: comic.id) {
                guard cover == nil else { return }
                let image = await library.coverImage(for: comic)
                withAnimation(.easeOut(duration: 0.2)) { cover = image }
            }
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .top, endPoint: .bottom)
            .overlay {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
            }
    }
}
