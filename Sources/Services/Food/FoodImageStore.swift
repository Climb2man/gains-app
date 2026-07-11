import Foundation
import UIKit

final class LocalFoodImageStore: FoodImageStore, @unchecked Sendable {
    /// The directory all food images live in, inside the app's Application Support container.
    private let directory: URL
    private let fileManager: FileManager

    /// Folder name under Application Support. Kept private to this feature so it can't collide.
    private static let folderName = "FoodImages"

    /// - Parameter fileManager: injected for tests; defaults to `.default`.
    /// - Throws: `FoodCaptureError.imageStore` if the container directory can't be created.
    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager

        let base = URL.applicationSupportDirectory.appending(path: Self.folderName, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            throw FoodCaptureError.imageStore
        }
        self.directory = base
        Self.excludeFromBackup(base)
    }

    /// Persist already-compressed JPEG bytes on-device (encrypted at rest) and return the relative path
    /// to reference it by (the `photo_local_path`). The capture flow hands the same bytes here and to
    /// the single vision call. Throws `FoodCaptureError.imageStore` on a write failure; never silently
    /// drops the photo.
    func save(imageJPEG: Data) async throws -> String {
        guard !imageJPEG.isEmpty else { throw FoodCaptureError.imageStore }
        let relativePath = "\(UUID().uuidString).jpg"
        let url = directory.appending(path: relativePath)
        do {
            try imageJPEG.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            throw FoodCaptureError.imageStore
        }
        return relativePath
    }

    /// Load a previously-saved image by its relative path for display (e.g. a thumbnail beside the
    /// logged line). Returns `nil` when the path no longer resolves so the UI simply omits the image.
    func loadImage(relativePath: String) -> UIImage? {
        guard let url = try? resolvedURL(for: relativePath),
              fileManager.fileExists(atPath: url.path(percentEncoded: false)),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    /// Delete a stored image (e.g. the user removes the logged line that owned it). Idempotent: a
    /// missing file is not an error.
    func delete(relativePath: String) {
        guard let url = try? resolvedURL(for: relativePath),
              fileManager.fileExists(atPath: url.path(percentEncoded: false))
        else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Resolve a stored relative path back to a URL inside this store's directory, rejecting anything
    /// that would escape it (defense against `../` traversal in a tampered path). The path is always a
    /// bare filename minted in `save`, so we accept only a single path component.
    private func resolvedURL(for relativePath: String) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              trimmed != ".", trimmed != ".."
        else {
            throw FoodCaptureError.imageStore
        }
        return directory.appending(path: trimmed)
    }

    /// Exclude a URL from iCloud/iTunes backup so food-photo PHI can't ride a backup off the device.
    /// Best-effort; a failure here doesn't block logging, and we never log the path.
    private static func excludeFromBackup(_ url: URL) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }
}
