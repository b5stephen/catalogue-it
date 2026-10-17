//
//  CameraPickerView.swift
//  catalogue-it
//
//  Created by Stephen Denekamp on 21/03/2026.
//

#if os(iOS)
import SwiftUI
import UIKit

/// Presented imperatively to get around SwiftUI's sheet nesting limits. Retain it for the
/// session: the picker's delegate reference is weak.
@MainActor
final class CameraCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onCapture: (UIImage) -> Void
    private let onDismiss: () -> Void
    private var hasPresented = false

    init(onCapture: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onDismiss = onDismiss
    }

    /// From `anchor`'s window: with several windows open, the first foreground scene may be
    /// a different one from the one the user asked from.
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
        picker.delegate = self
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

/// Presents `coordinator`'s camera from this view's window. Place it on the control that
/// requests the camera, so it stays mounted for the session.
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
