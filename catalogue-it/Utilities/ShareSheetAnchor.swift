//
//  ShareSheetAnchor.swift
//  catalogue-it
//

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Share Sheet Anchor

/// `ShareLink` can't live in a `.secondaryAction` item: chosen from the bar's overflow menu it
/// closes the menu and its own anchor, and on iOS 26 the share popover then aborts the app for
/// want of a `sourceView`. Place this where it outlives that menu, near the button the popover
/// should point at.
struct ShareSheetAnchor: UIViewRepresentable {
    @Binding var itemProvider: NSItemProvider?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let provider = itemProvider else { return }
        // Deferred a turn: state can't be written inside an update. Clearing first means a
        // re-render can't present it twice.
        Task {
            itemProvider = nil
            Self.present(provider, from: uiView)
        }
    }

    private static func present(_ provider: NSItemProvider, from anchor: UIView) {
        guard var presenter = anchor.owningViewController else { return }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        let configuration = UIActivityItemsConfiguration(itemProviders: [provider])
        // The file name as the header, as `ShareLink`'s preview gave it.
        let title = provider.suggestedName
        configuration.metadataProvider = { key in
            key == .title ? title : nil
        }
        let controller = UIActivityViewController(activityItemsConfiguration: configuration)
        controller.popoverPresentationController?.sourceView = anchor
        controller.popoverPresentationController?.sourceRect = anchor.bounds
        presenter.present(controller, animated: true)
    }
}

private extension UIView {
    var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
#endif
