//
//  CameraPickerView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 21/03/2026.
//

#if os(iOS)
import UIKit

/// Imperatively presents UIImagePickerController from the topmost UIViewController,
/// bypassing SwiftUI's sheet nesting restrictions.
/// Must be retained externally (e.g. via @State) for the duration of the session,
/// since UIImagePickerController.delegate is a weak reference.
@MainActor
final class CameraCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onCapture: (UIImage) -> Void
    private let onDismiss: () -> Void

    init(onCapture: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onDismiss = onDismiss
    }

    func present() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else {
            onDismiss()
            return
        }

        var topVC = root
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = self  // retains self for the session
        topVC.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
            onCapture(image)
        }
        onDismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        onDismiss()
    }
}
#endif
