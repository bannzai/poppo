import SwiftUI

/// 取り込みを始める入口。最初の画面の下端に出し、同意の画面へ進ませる。直前の取り込みがエラーで止まった時はそのことも出す
struct ScreenCaptureEntryView: View {
    /// 今の取り込みの状態
    let status: ScreenCaptureStatus
    /// 取り込みが終わった時に、読み取り結果を削除できなかったか
    let failedToDeleteLatestReading: Bool
    /// 入口を押した時に呼ぶ処理。同意の画面を開く
    let openConsent: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if status == .failed {
                ScreenCaptureFailedText()
            }
            if failedToDeleteLatestReading {
                // ja: キーボードに出す翻訳を消せませんでした
                Text("Couldn't clear the translations shown on the keyboard")
                    .font(.footnote)
                    .foregroundStyle(.poppoError)
                    .accessibilityIdentifier("screen_capture_delete_failed")
            }
            Button(action: openConsent) {
                // ja: 画面の取り込みを始める
                Label("Start screen capture", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PoppoTintedButtonStyle())
            .accessibilityIdentifier("screen_capture_start_link")
        }
        .padding()
        .background(.poppoBackground)
    }
}

/// 取り込みを始める前の同意の画面。何を読むか・端末の外へ送らないこと・いつでも止められることを説明し、同意の操作で取り込みを始める。
/// 取り込みが始まった時にこの画面を閉じるのは、この画面を開いた側 (ContentView) が行う
struct ScreenCaptureConsentView: View {
    /// 今の取り込みの状態
    let status: ScreenCaptureStatus
    /// 利用者が同意した時に呼ぶ処理。取り込む対象を選ぶシステムの画面を出す
    let start: () -> Void

    var body: some View {
        List {
            Section {
                // ja: 取り込み中は他のアプリを含む画面全体の文字を読み取ります
                Label("The text on your entire screen including other apps is read while screen capture is on", systemImage: "text.viewfinder")
                // ja: 画面の映像は保存せずこの端末の外へ送りません
                Label("The screen video is never saved and never leaves this device", systemImage: "lock")
                // ja: このアプリからいつでも止められます
                Label("You can stop anytime from this app", systemImage: "stop.circle")
            } header: {
                // ja: 始める前に
                Text("Before you start")
            }
            .listRowBackground(Color.poppoSurface)
            Section {
                Button(action: start) {
                    // ja: 同意して始める
                    Text("Agree and start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PoppoFilledButtonStyle(fill: .poppoAccent, label: .poppoOnAccent))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("screen_capture_consent_button")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    // ja: 次に出るシステムの画面で画面全体を選んでください
                    Text("Choose your entire screen on the next system screen")
                    if status == .failed {
                        ScreenCaptureFailedText()
                    }
                }
            }
        }
        .poppoScreenBackground()
        // ja: 画面の取り込み
        .navigationTitle(Text("Screen capture"))
    }
}

/// 取り込み中であることと、停止の操作を出す帯。取り込み中は、本体アプリのどの画面でも下端に出す。
/// 直前の停止の操作で止められなかった時は、そのことも出す (停止の操作はそのまま出し、もう一度止められるようにする)
struct ScreenCaptureCapturingBar: View {
    /// 直前の停止の操作で、取り込みを止められなかったか
    let failedToStop: Bool
    /// 停止の操作をした時に呼ぶ処理。取り込みを止める
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if failedToStop {
                // ja: 画面の取り込みを止められませんでした
                Text("Couldn't stop screen capture")
                    .font(.footnote)
                    .foregroundStyle(.poppoError)
                    .accessibilityIdentifier("screen_capture_stop_failed")
            }
            HStack {
                Label {
                    // ja: 画面を取り込んでいます
                    Text("Capturing your screen")
                } icon: {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.poppoError)
                }
                .accessibilityIdentifier("screen_capture_capturing_label")
                Spacer()
                Button(role: .destructive, action: stop) {
                    // ja: 停止
                    Text("Stop")
                }
                .buttonStyle(PoppoFilledButtonStyle(fill: .poppoError, label: .poppoOnError))
                .accessibilityIdentifier("screen_capture_stop_button")
            }
        }
        .padding()
        .background(.poppoSurface)
    }
}

/// 取り込みがエラーで始められなかった、または止まったことを伝える文
private struct ScreenCaptureFailedText: View {
    var body: some View {
        // ja: エラーで画面の取り込みが止まりました
        Text("Screen capture stopped because of an error")
            .font(.footnote)
            .foregroundStyle(.poppoError)
            .accessibilityIdentifier("screen_capture_failed")
    }
}
