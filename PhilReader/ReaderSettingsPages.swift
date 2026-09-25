import SwiftUI

// MARK: - Gestures and zoom

struct GesturesSettingsView: View {
    @AppStorage("reader.tapToTurn") private var tapToTurn = true
    @AppStorage(ReaderKeys.leftTap) private var leftTap: EdgeTapAction = .turnTowardSide
    @AppStorage(ReaderKeys.rightTap) private var rightTap: EdgeTapAction = .turnTowardSide
    @AppStorage(ReaderKeys.tapZone) private var tapZone: TapZoneSize = .medium
    @AppStorage(ReaderKeys.doubleTapZoom) private var doubleTapZoom: DoubleTapZoom = .medium
    @AppStorage(ReaderKeys.dragToClose) private var dragToClose = true

    var body: some View {
        Form {
            Section {
                TapZonePreview(zone: tapZone.fraction, enabled: tapToTurn, left: leftTap, right: rightTap)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                Toggle(isOn: $tapToTurn) {
                    SettingsLabel("Tap Sides to Turn Pages", systemImage: "hand.tap")
                }
                if tapToTurn {
                    Picker(selection: $leftTap) {
                        ForEach(EdgeTapAction.allCases) { Text($0.label).tag($0) }
                    } label: {
                        SettingsLabel("Left Side", systemImage: "rectangle.lefthalf.inset.filled")
                    }
                    Picker(selection: $rightTap) {
                        ForEach(EdgeTapAction.allCases) { Text($0.label).tag($0) }
                    } label: {
                        SettingsLabel("Right Side", systemImage: "rectangle.righthalf.inset.filled")
                    }
                    Picker(selection: $tapZone) {
                        ForEach(TapZoneSize.allCases) { Text($0.label).tag($0) }
                    } label: {
                        SettingsLabel("Side Width", systemImage: "arrow.left.and.right")
                    }
                }
            } header: {
                Text("Taps")
            } footer: {
                Text("Tapping the middle of the page always shows or hides the controls. \u{201C}Turn Page Toward Side\u{201D} follows the reading direction, so the left side moves forward in manga.")
            }

            Section {
                Picker(selection: $doubleTapZoom) {
                    ForEach(DoubleTapZoom.allCases) { Text($0.label).tag($0) }
                } label: {
                    SettingsLabel("Double-Tap Zoom", systemImage: "plus.magnifyingglass")
                }
            } header: {
                Text("Zoom")
            } footer: {
                Text("Pinch to zoom any amount. Double-tap again to zoom back out. Turning double-tap zoom off makes single taps respond instantly.")
            }

            Section {
                Toggle(isOn: $dragToClose) {
                    SettingsLabel("Drag Down to Close", systemImage: "arrow.down.to.line")
                }
            } footer: {
                Text("Pull down from the top of the page to close the comic, in either reader.")
            }
        }
        .navigationTitle("Gestures and Zoom")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A phone outline showing which parts of the screen turn pages.
private struct TapZonePreview: View {
    let zone: CGFloat
    let enabled: Bool
    let left: EdgeTapAction
    let right: EdgeTapAction

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width * zone
            HStack(spacing: 0) {
                region(enabled ? short(left, isLeft: true) : "Controls", active: enabled && left != .nothing)
                    .frame(width: enabled ? side : 0)
                    .opacity(enabled ? 1 : 0)
                region("Controls", active: false)
                region(enabled ? short(right, isLeft: false) : "Controls", active: enabled && right != .nothing)
                    .frame(width: enabled ? side : 0)
                    .opacity(enabled ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary, lineWidth: 1))
        }
        .frame(height: 120)
        .animation(.easeInOut(duration: 0.2), value: zone)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .accessibilityHidden(true)
    }

    private func region(_ title: String, active: Bool) -> some View {
        ZStack {
            if active { Color.accentColor.opacity(0.18) } else { Color.secondary.opacity(0.08) }
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                .padding(4)
        }
    }

    private func short(_ action: EdgeTapAction, isLeft: Bool) -> String {
        switch action {
        case .turnTowardSide: return isLeft ? "Page\nLeft" : "Page\nRight"
        case .nextPage: return "Next"
        case .previousPage: return "Previous"
        case .toggleControls: return "Controls"
        case .nothing: return "Nothing"
        }
    }
}

// MARK: - Image filters

struct ImageFiltersView: View {
    @AppStorage(ReaderKeys.filters) private var stored = StoredFilters()
    @AppStorage(ReaderKeys.filtersEnabled) private var enabled = false

    private var filters: Binding<ImageFilterSettings> {
        Binding(get: { stored.value }, set: { stored = StoredFilters($0) })
    }

    var body: some View {
        Form {
            Section {
                FilterPreview(filters: enabled ? stored.value : nil)
                    .listRowInsets(EdgeInsets())
                Toggle(isOn: $enabled) {
                    SettingsLabel("Image Filters", systemImage: "camera.filters")
                }
            } footer: {
                Text("Adjust scans that are too dark, washed out or yellowed. Filters apply to every comic.")
            }

            Section("Tone") {
                Picker("Tone", selection: filters.tone) {
                    ForEach(ImageTone.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .disabled(!enabled)

            Section("Adjustments") {
                slider("Brightness", systemImage: "sun.max", value: filters.brightness,
                       in: ImageFilterSettings.brightnessRange, neutral: 0)
                slider("Contrast", systemImage: "circle.righthalf.filled", value: filters.contrast,
                       in: ImageFilterSettings.contrastRange, neutral: 1)
                Button("Reset") { stored = StoredFilters() }
                    .disabled(stored.value.isOriginal)
            }
            .disabled(!enabled)
        }
        .navigationTitle("Image Filters")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func slider(_ title: String, systemImage: String, value: Binding<Double>,
                        in range: ClosedRange<Double>, neutral: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SettingsLabel(title, systemImage: systemImage)
                Spacer()
                Text(String(format: "%+.0f", (value.wrappedValue - neutral) * 100))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
        .padding(.vertical, 2)
    }
}

/// A drawn sample page, so filter changes can be judged without opening a comic.
private struct FilterPreview: View {
    let filters: ImageFilterSettings?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { index in
                samplePanel(index)
            }
        }
        .padding(14)
        .frame(height: 150)
        .background(Color(white: 0.96))
        .pageFilters(filters)
        .environment(\.colorScheme, .light)
    }

    private func samplePanel(_ index: Int) -> some View {
        let hues: [Double] = [0.58, 0.08, 0.9]
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hue: hues[index], saturation: 0.55, brightness: 0.95),
                                    Color(hue: hues[index], saturation: 0.8, brightness: 0.45)],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: 34)
                .offset(x: 14, y: -54)
            Text(["BAM!", "…", "WHOA"][index])
                .font(.system(size: 13, weight: .black))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.black)
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Presets

struct PresetsView: View {
    @AppStorage(ReaderKeys.presets) private var custom = PresetList()
    @State private var naming = false
    @State private var newName = ""
    @State private var appliedID: UUID?

    var body: some View {
        List {
            Section {
                ForEach(ReaderPreset.builtIn) { row($0) }
            } header: {
                Text("Built In")
            } footer: {
                Text("Applying a preset makes it the default for new comics and switches the comic you're reading. Each comic still remembers its own layout and direction.")
            }

            Section("Your Presets") {
                ForEach(custom.items) { row($0) }
                    .onDelete { offsets in custom.items.remove(atOffsets: offsets) }
                Button {
                    newName = ""
                    naming = true
                } label: {
                    SettingsLabel("Save Current Settings…", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Presets")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Preset", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                custom.items.append(ReaderPreset.current(named: name.isEmpty ? "My Preset" : name))
            }
        } message: {
            Text("Saves your current reading mode, direction, page fit, page turn, guided view, background and image filters.")
        }
    }

    private func row(_ preset: ReaderPreset) -> some View {
        Button {
            preset.apply()
            withAnimation { appliedID = preset.id }
        } label: {
            HStack(spacing: 14) {
                SettingsIcon(systemImage: icon(for: preset))
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).foregroundStyle(.primary)
                    Text(preset.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if appliedID == preset.id {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
        }
    }

    private func icon(for preset: ReaderPreset) -> String {
        if preset.mode == .vertical { return "arrow.down.doc" }
        if preset.guided { return "viewfinder" }
        return preset.rightToLeft ? "arrow.left.square" : "arrow.right.square"
    }
}
