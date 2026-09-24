import SwiftUI
import VisionKit

struct ReaderSettingsSheet: View {
    @Binding var mode: ReadingMode
    @Binding var isRightToLeft: Bool
    @Binding var guidedView: Bool
    @Binding var fit: PageFit
    @Binding var spreadsInLandscape: Bool
    @Binding var background: ReaderBackground
    @Binding var tapToTurn: Bool
    @Binding var liveText: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Layout", selection: $mode) {
                        ForEach(ReadingMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if mode == .paged {
                        Picker("Direction", selection: $isRightToLeft) {
                            Text("Right to Left").tag(true)
                            Text("Left to Right").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("This Comic")
                } footer: {
                    Text(mode == .paged
                         ? "Right to left is the traditional layout for manga. New comics use your latest choice unless their metadata says otherwise."
                         : "Vertical scroll shows pages as one continuous strip, ideal for webtoons.")
                }

                if mode == .paged {
                    Section {
                        Picker("Fit", selection: $fit) {
                            ForEach(PageFit.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Guided View", isOn: $guidedView)
                        Toggle("Two-Page Spreads in Landscape", isOn: $spreadsInLandscape)
                            .disabled(guidedView)
                    } header: {
                        Text("Page Layout")
                    } footer: {
                        Text("Guided View zooms to one panel at a time; tap the edges or use the arrow keys to move between panels. Fit Width fills the screen edge to edge. Spreads show facing pages side by side, with the cover and wide pages on their own.")
                    }
                }

                Section("Background") {
                    HStack(spacing: 14) {
                        ForEach(ReaderBackground.allCases) { option in
                            Button { background = option } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 38, height: 38)
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.accentColor, lineWidth: 3)
                                                .padding(-5)
                                                .opacity(background == option ? 1 : 0)
                                        )
                                    Text(option.label)
                                        .font(.caption)
                                        .foregroundStyle(background == option ? Color.primary : Color.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Toggle("Tap Edges to Turn Pages", isOn: $tapToTurn)
                    if ImageAnalyzer.isSupported {
                        Toggle("Live Text", isOn: $liveText)
                    }
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Tap the middle of a page to show or hide the controls. Double-tap or pinch to zoom. With Live Text, touch and hold text on a page to copy or translate it.")
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

extension ReaderBackground {
    var color: Color {
        switch self {
        case .black: return .black
        case .gray: return Color(white: 0.16)
        case .white: return Color(white: 0.97)
        }
    }

    var colorScheme: ColorScheme { self == .white ? .light : .dark }
}
