//
//  ShareSheetAnchor.swift
//  catalogue-it
//

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Share Sheet Content

enum ShareSheetContent {
    /// Built on demand when a destination asks.
    case itemProviders([NSItemProvider])
    /// A file already on disk. On the Mac, Save to Files names its save panel from the shared
    /// item's URL; given an item provider it gets none and AppKit aborts the app.
    case file(URL)
}

// MARK: - Share Sheet Anchor

/// `ShareLink` can't live in a `.secondaryAction` item: chosen from the bar's overflow menu it
/// closes the menu and its own anchor, and on iOS 26 the share popover then aborts the app for
/// want of a `sourceView`. Place this where it outlives that menu, near the button the popover
/// should point at.
struct ShareSheetAnchor: UIViewRepresentable {
    @Binding var content: ShareSheetContent?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let content else { return }
        if case .itemProviders(let providers) = content, providers.isEmpty { return }
        // Deferred a turn: state can't be written inside an update. Clearing first means a
        // re-render can't present it twice.
        Task {
            self.content = nil
            Self.present(content, from: uiView)
        }
    }

    private static func present(_ content: ShareSheetContent, from anchor: UIView) {
        guard var presenter = anchor.owningViewController else { return }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        let controller: UIActivityViewController
        switch content {
        case .itemProviders(let providers):
            let configuration = UIActivityItemsConfiguration(itemProviders: providers)
            // The first provider's name as the header, as `ShareLink`'s preview gave it.
            let title = providers.first?.suggestedName
            configuration.metadataProvider = { key in
                key == .title ? title : nil
            }
            controller = UIActivityViewController(activityItemsConfiguration: configuration)
        case .file(let url):
            controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        }
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
