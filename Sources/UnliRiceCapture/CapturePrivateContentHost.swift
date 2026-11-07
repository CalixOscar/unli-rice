import SwiftUI
import UIKit

private struct CaptureEnvironmentBridge<Content: View>: View {
    let content: Content
    let values: EnvironmentValues
    let concealed: Bool

    var body: some View {
        content.accessibilityElement(children: concealed ? .ignore : .contain)
            .accessibilityHidden(concealed)
            .allowsHitTesting(!concealed)
            .environment(\.self, values)
    }
}

private final class CapturePrivateContainer<Content: View>: UIViewController {
    let hosting: UIHostingController<CaptureEnvironmentBridge<Content>>

    init(content: Content, values: EnvironmentValues, concealed: Bool) {
        hosting = UIHostingController(rootView: CaptureEnvironmentBridge(content: content, values: values, concealed: concealed))
        hosting.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    func setConcealed(_ concealed: Bool) {
        if concealed { view.endEditing(true) }
        view.accessibilityElementsHidden = concealed
        view.isUserInteractionEnabled = !concealed
        hosting.view.isHidden = concealed
    }
}

struct CapturePrivateContentHost<Content: View>: UIViewControllerRepresentable {
    @Environment(\.self) private var values
    let content: Content
    let concealed: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = CapturePrivateContainer(content: content, values: values, concealed: concealed)
        controller.loadViewIfNeeded()
        controller.setConcealed(concealed)
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let controller = controller as? CapturePrivateContainer<Content> else { return }
        controller.setConcealed(concealed)
        controller.hosting.rootView = CaptureEnvironmentBridge(content: content, values: values, concealed: concealed)
    }
}
