//
//  PhotoLibrarySaver.swift
//  catalogue-it
//

#if os(iOS)
import Photos
import os

/// Best effort: denial or failure is logged and ignored. Call from a non-blocking `Task`.
enum PhotoLibrarySaver {
    nonisolated private static let logger = Logger(subsystem: "catalogue-it", category: "PhotoLibrarySaver")

    nonisolated static func saveIfAuthorized(_ jpegData: Data) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            logger.notice("Skipping camera-roll save: Photos add-only access not granted.")
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpegData, options: nil)
            }
        } catch {
            logger.error("Failed to save captured photo to camera roll: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
