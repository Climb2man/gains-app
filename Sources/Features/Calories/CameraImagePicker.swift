import SwiftUI
import UIKit

struct CameraImagePicker: UIViewControllerRepresentable {
    /// Called with the captured image as compressed JPEG bytes.
    let onCapture: (Data) -> Void
    /// Called when the user cancels or the camera is unavailable.
    let onCancel: () -> Void

    /// JPEG quality: small enough for a cheap base64 vision call, sharp enough to read a plate or label.
    private static let jpegQuality: CGFloat = 0.7

    /// Longest-side pixel cap before encoding. Providers downscale to ~1.5K px anyway, so a
    /// full-resolution capture only costs memory and upload bytes, not accuracy.
    private static let maxPixelDimension: CGFloat = 1536

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    /// Aspect-fit downscale to `maxPixelDimension`, then JPEG-encode. Runs off the main thread since a
    /// full-resolution decode/scale/encode is expensive. Shared by the camera and label paths.
    static func compressedJPEG(from image: UIImage) async -> Data? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longestSide = max(pixelSize.width, pixelSize.height)
        var scaled = image
        if longestSide > maxPixelDimension {
            let ratio = maxPixelDimension / longestSide
            let target = CGSize(width: pixelSize.width * ratio, height: pixelSize.height * ratio)
            if let thumbnail = await image.byPreparingThumbnail(ofSize: target) {
                scaled = thumbnail
            }
        }
        return scaled.jpegData(compressionQuality: jpegQuality)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onCancel()
                return
            }
            Task.detached(priority: .userInitiated) { [parent = self.parent] in
                let data = await CameraImagePicker.compressedJPEG(from: image)
                await MainActor.run {
                    if let data {
                        parent.onCapture(data)
                    } else {
                        parent.onCancel()
                    }
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
