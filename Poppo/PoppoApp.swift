import SwiftUI

/// 本体アプリの入口。ホーム画面から開いた時の最初の画面を出す
@main
struct PoppoApp: App {
    /// 取り込みの状態。どの画面へ進んでも取り込み中の表示と停止の操作を出せるよう、アプリの入口で 1 つだけ持つ
    @State private var screenCaptureController = makeOnDeviceScreenCaptureController(
        latestReadingFileURL: latestReadingFileURL(),
        diagnosticsFileURL: screenCaptureDiagnosticsFileURL()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(screenCaptureController)
        }
    }
}

/// 本体アプリが使う取り込みの状態を作って返す。取り込みの実体と、取り込んだ画面を読む処理 (文字の読み取り・翻訳・返信案の生成) には、
/// 本物を使う (返信案は、選ばれているモデルで作る)。latestReadingFileURL は読み取り結果を置く場所、diagnosticsFileURL は診断の記録を置く場所
func makeOnDeviceScreenCaptureController(latestReadingFileURL: URL?, diagnosticsFileURL: URL?) -> ScreenCaptureController {
    ScreenCaptureController(
        makeSource: makeScreenCaptureSource,
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: diagnosticsFileURL,
        now: { Date() },
        recognizeTextLines: { try await recognizeTextLines(image: $0) },
        translateTexts: {
            try await translateOnDevice(texts: $0, targetLanguage: userLanguage(preferredLanguages: Locale.preferredLanguages))
        },
        selectedReplyModel: { selectedReplyModel(userDefaults: .standard) },
        canGenerateReplies: { canGenerateReplies(replyModel: $0) },
        generateReplyTexts: { try await generateReplyTexts(messages: $0, replyModel: $1) },
        wait: { try? await Task.sleep(for: .seconds($0)) }
    )
}

/// 診断の記録を置くファイルの場所を返す。診断の記録は DEBUG ビルドでだけ保存するため、それ以外のビルドでは nil を返す
func screenCaptureDiagnosticsFileURL() -> URL? {
    #if DEBUG
    return URL.applicationSupportDirectory.appending(path: "screen-capture-diagnostics.json")
    #else
    return nil
    #endif
}
