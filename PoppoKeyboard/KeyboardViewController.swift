import SwiftUI
import UIKit

/// カスタムキーボードの入口。本体アプリが保存した読み取り結果を出す画面を載せ、返信案のタップを入力欄への入力につなぐ
final class KeyboardViewController: UIInputViewController {
    /// キーボードの画面を載せている controller。viewDidLoad で作るまでは nil
    private var hostingController: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let hosting = UIHostingController(rootView: keyboardView())
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
        hostingController = hosting
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // needsInputModeSwitchKey をレイアウトのたびに読み直す。Xcode のキーボードのテンプレート
        // (Custom Keyboard Extension の KeyboardViewController.swift) が viewWillLayoutSubviews で読んでいるのに合わせた。
        // 値が変わった時だけ画面を作り直す (毎回作り直すと、作り直しがまたレイアウトを起こす)
        guard let hostingController, hostingController.rootView.needsInputModeSwitchKey != needsInputModeSwitchKey else {
            return
        }
        hostingController.rootView = keyboardView()
    }

    /// 今の needsInputModeSwitchKey の値で、キーボードの画面を作って返す
    private func keyboardView() -> KeyboardView {
        KeyboardView(
            needsInputModeSwitchKey: needsInputModeSwitchKey,
            onSwitchKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            latestReadingFileURL: latestReadingFileURL(),
            onInsertText: { [weak self] in self?.textDocumentProxy.insertText($0) }
        )
    }
}
