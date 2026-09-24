import SwiftUI

/// A grid of page thumbnails for jumping around a comic, with a bookmarks filter.
struct PageBrowserView: View {
    let model: ReaderModel
    let currentIndex: Int
    let bookmarks: [Int]
    let select: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsBookmarks = false

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 14)]

    private var pages: [Int] {
        showsBookmarks ? bookmarks.filter { $0 < model.pageCount } : Array(0..<model.pageCount)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    if pages.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 34))
                                .foregroundStyle(.tertiary)
                            Text("No Bookmarks")
                                .font(.headline)
                            Text("Tap the bookmark button while reading to mark a page.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 80)
                        .padding(.horizontal, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(pages, id: \.self) { index in
                                Button {
                                    select(index)
                                    dismiss()
                                } label: {
                                    PageThumbnail(index: index, model: model,
                                                  isCurrent: index == currentIndex,
                                                  isBookmarked: bookmarks.contains(index))
                                }
                                .buttonStyle(CoverButtonStyle())
                                .id(index)
                            }
                        }
                        .padding(16)
                    }
                }
                .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $showsBookmarks) {
                        Text("All Pages").tag(false)
                        Text("Bookmarks").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PageThumbnail: View {
    let index: Int
    let model: ReaderModel
    let isCurrent: Bool
    let isBookmarked: Bool

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Color.primary.opacity(0.06)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .transition(.opacity)
                    } else {
                        ProgressView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 3)
                )
                .overlay(alignment: .topTrailing) {
                    if isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .padding(6)
                    }
                }

            Text("\(index + 1)")
                .font(.caption.weight(isCurrent ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
        }
        .task(id: index) {
            let loaded = await model.thumbnail(at: index)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }
}
