import UIKit
import SwiftUI

/// NSExtension entry point. Embeds the SwiftUI share flow inside a UIHostingController.
@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let context = extensionContext else { return }

        let viewModel  = ShareViewModel(extensionContext: context)
        let rootView   = ShareRootView(viewModel: viewModel)
        let hosting    = UIHostingController(rootView: rootView)

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}
