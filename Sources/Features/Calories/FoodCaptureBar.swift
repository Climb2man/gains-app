import PhotosUI
import SwiftUI

struct FoodCaptureBar: View {
    let coordinator: FoodCaptureCoordinator
    /// The host's barcode entry point (a self-contained scanner flow).
    let onScanBarcode: () -> Void

    /// Which capture a pending PhotosPicker selection should be routed to (food / menu / package).
    @State private var pickerTarget: PickerTarget?
    /// The PhotosPicker selection, decoded to JPEG and dispatched on change.
    @State private var pickedItem: PhotosPickerItem?
    /// Whether the camera capture sheet is showing, and for which target.
    @State private var cameraTarget: PickerTarget?

    enum PickerTarget: Identifiable {
        case food, menu, package
        var id: Int { hashValue }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CaptureActionButton(
                title: "Camera", systemImage: "camera.fill",
                hint: "Take a photo of your food to estimate macros",
                busy: coordinator.isBusy
            ) { cameraTarget = .food }

            photoMenu

            CaptureActionButton(
                title: "Menu", systemImage: "doc.text.viewfinder",
                hint: "Scan a restaurant menu and pick what you ate",
                busy: coordinator.isBusy
            ) { cameraTarget = .menu }

            CaptureActionButton(
                title: "Barcode", systemImage: "barcode.viewfinder",
                hint: "Scan a product barcode to look it up",
                busy: coordinator.isBusy
            ) { onScanBarcode() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .disabled(coordinator.isBusy)
        .opacity(coordinator.isBusy ? 0.5 : 1)
        .background(Theme.Colors.surface)
        .accessibilityLabel("Capture food from a photo, menu, or barcode")
        .photosPicker(
            isPresented: photosPickerPresented,
            selection: $pickedItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: pickedItem) { _, newValue in
            guard let newValue, let target = pickerTarget else { return }
            loadAndDispatch(newValue, target: target)
        }
        .fullScreenCover(item: $cameraTarget) { target in
            CameraImagePicker { jpeg in
                cameraTarget = nil
                dispatch(jpeg, target: target)
            } onCancel: {
                cameraTarget = nil
            }
            .ignoresSafeArea()
        }
    }

    private var photoMenu: some View {
        Menu {
            Button("Food photo", systemImage: "fork.knife") { present(.food) }
            Button("Menu photo", systemImage: "doc.text.viewfinder") { present(.menu) }
            Button("Package label", systemImage: "shippingbox") { present(.package) }
        } label: {
            CaptureActionLabel(title: "Photo", systemImage: "photo", busy: coordinator.isBusy)
        }
        .accessibilityLabel("Choose a food, menu, or package photo from your library")
    }

    /// A binding that presents the library picker whenever a target is set by the photo menu.
    private var photosPickerPresented: Binding<Bool> {
        Binding(
            get: { pickerTarget != nil && pickedItem == nil },
            set: { if !$0 { pickerTarget = nil } }
        )
    }

    private func present(_ target: PickerTarget) {
        pickedItem = nil
        pickerTarget = target
    }

    private func loadAndDispatch(_ item: PhotosPickerItem, target: PickerTarget) {
        Task {
            let jpeg = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                pickedItem = nil
                pickerTarget = nil
                if let jpeg { dispatch(jpeg, target: target) }
            }
        }
    }

    private func dispatch(_ jpeg: Data, target: PickerTarget) {
        switch target {
        case .food: coordinator.handleFoodPhoto(jpeg)
        case .menu: coordinator.handleMenuPhoto(jpeg)
        case .package: coordinator.handlePackagePhoto(jpeg)
        }
    }
}

/// One capture action tile. Styled as content, not chrome: the glyph rests at `labelSecondary` on
/// `surface2` and only tints on press, so blue stays reserved for chrome.
private struct CaptureActionButton: View {
    let title: String
    let systemImage: String
    let hint: String
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CaptureActionLabel(title: title, systemImage: systemImage, busy: busy)
        }
        .buttonStyle(CaptureTileButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

/// The tile shared by the capture buttons and the photo `Menu` trigger: a grey glyph over a caption on
/// `surface2`, equal-width so the four actions line up. While busy the glyph bounces, unless Reduce
/// Motion is on (the dimmed, disabled bar still signals busy).
private struct CaptureActionLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let systemImage: String
    var busy: Bool = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            glyph
            Txt(title, variant: .footnote, color: .labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Colors.surface2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        }
    }

    private var glyph: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Colors.labelSecondary)
            .symbolEffect(.bounce, options: .repeating, isActive: busy && !reduceMotion)
            .frame(width: 30, height: 30)
            .background(Theme.Colors.surface, in: .circle)
    }
}

private struct CaptureTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("Capture bar") {
    FoodCaptureBar(coordinator: .preview, onScanBarcode: {})
        .background(Theme.Colors.background)
}
#endif
