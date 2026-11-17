import SwiftUI
import UIKit

/// カスタムキーボードの入口。立ち上げ時点では仮の表示だけを持ち、翻訳と返信案の表示は後の実装で足す
final class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hosting = UIHostingController(
            rootView: KeyboardView(
                needsInputModeSwitchKey: needsInputModeSwitchKey,
                onSwitchKeyboard: { [weak self] in self?.advanceToNextInputMode() }
            )
        )
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }
}
