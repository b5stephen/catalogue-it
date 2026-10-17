//
//  CameraPickerView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 21/03/2026.
//

#if os(iOS)
import SwiftUI
import UIKit

/// Imperatively presents UIImagePickerController from the topmost UIViewController,
/// bypassing SwiftUI's sheet nesting restrictions.
/// Must be retained externally (e.g. via @State) for the duration of the session,
/// since UIImagePickerController.delegate is a weak reference.
@MainActor
final class CameraCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onCapture: (UIImage) -> Void
    private let onDismiss: () -> Void
    private var hasPresented = false

    init(onCapture: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onDismiss = onDismiss
    }

    /// Presents over the window `anchor` is in — the one the user asked from. With more than
    /// one window open, "the first foreground scene" can be a different one.
    func present(from anchor: UIView) {
        guard !hasPresented else { return }
        hasPresented = true
        guard let root = anchor.window?.rootViewController else {
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

/// Presents `coordinator`'s camera from the window this view sits in. Place it on the control
/// that requests the camera, where it stays mounted for the session.
struct CameraPresentationAnchor: UIViewRepresentable {
    let coordinator: CameraCoordinator?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let coordinator else { return }
        // Deferred a turn: presenting can call back into state, which can't be written from
        // inside an update. The coordinator ignores repeat requests from later re-renders.
        Task { coordinator.present(from: uiView) }
    }
}
#endif
