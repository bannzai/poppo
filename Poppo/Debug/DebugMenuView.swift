#if DEBUG
import SwiftUI

/// 開発者メニュー。simulator では動かない処理 (翻訳・返信案の生成・言語のダウンロード) を通さずに、その先の画面を確かめるための入口。
/// DEBUG ビルドにだけ入る。どの操作も画面を開くだけで、データを書き換えない
struct DebugMenuView: View {
    var body: some View {
        List {
            NavigationLink {
                ChatReadingResultView(messages: debugSampleMessages, replySuggestions: debugSampleReplySuggestions)
            } label: {
                Text(verbatim: "見本の読み取り結果を開く")
            }
            .accessibilityIdentifier("debug_open_sample_result")
            NavigationLink {
                ChatReadingResultView(messages: debugSampleMessages, replySuggestions: [])
            } label: {
                Text(verbatim: "見本の読み取り結果を開く (返信案なし)")
            }
            .accessibilityIdentifier("debug_open_sample_result_without_replies")
            NavigationLink {
                ChatReadingPhaseView(
                    phase: .needsLanguageDownload(
                        source: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: "ja")
                    ),
                    downloadLanguage: { _, _ in },
                    retry: {}
                )
            } label: {
                Text(verbatim: "言語のダウンロードを促す画面を開く")
            }
            .accessibilityIdentifier("debug_open_language_download")
        }
        .navigationTitle(Text(verbatim: "開発者メニュー"))
    }
}

/// 開発者メニューで結果の画面を開く時に出す、見本の発言と翻訳
private let debugSampleMessages = [
    TranslatedMessage(
        originalText: "Hey, are you free for a quick call this afternoon?",
        translatedText: "今日の午後、少し通話する時間はありますか？"
    ),
    TranslatedMessage(
        originalText: "I want to go over the release plan before Friday.",
        translatedText: "金曜日までにリリースの計画を確認しておきたいです。"
    ),
]

/// 開発者メニューで結果の画面を開く時に出す、見本の返信案
private let debugSampleReplySuggestions = [
    ReplySuggestion(text: "Sure, I'm free after 3 pm.", meaning: "はい、15 時以降なら空いています。"),
    ReplySuggestion(text: "Can we do it tomorrow morning instead?", meaning: "代わりに明日の午前でもいいですか？"),
    ReplySuggestion(text: "Sorry, I'm busy today. Could you send me the plan first?", meaning: "すみません、今日は忙しいです。先に計画を送ってもらえますか？"),
]
#endif
