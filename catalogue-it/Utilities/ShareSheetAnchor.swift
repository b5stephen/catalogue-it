//
//  ShareSheetAnchor.swift
//  catalogue-it
//

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Share Sheet Anchor

/// Presents the system share sheet for `itemProvider`, anchored on this view, then clears it.
///
/// Exists because `ShareLink` can't live in a `.secondaryAction` toolbar item. When the bar is
/// short of room iOS folds those items into its own "…" overflow menu, and choosing a
/// `ShareLink` there closes the menu — taking the view the share sheet anchors on with it.
/// On iOS 26 the share sheet is a popover even on iPhone, so UIKit then throws for want of a
/// `sourceView` and the app aborts. Place this where it stays on screen for as long as the
/// menu that requests the share, near the button the popover should point at.
struct ShareSheetAnchor: UIViewRepresentable {
    @Binding var itemProvider: NSItemProvider?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let provider = itemProvider else { return }
        // Deferred a turn: state can't be written from inside an update, and clearing the
        // request first means a re-render can never present it twice.
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
        // The file name as the sheet's header, as `ShareLink`'s preview gave it.
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
