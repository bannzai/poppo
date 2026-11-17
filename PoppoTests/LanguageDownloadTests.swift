import Foundation
import Testing
import Translation
@testable import Poppo

/// 言語のダウンロードを初めて選んだ時は、渡した言語の組の設定を返すこと
@Test func nextLanguageDownloadConfigurationStartsWithGivenLanguages() {
    let next = nextLanguageDownloadConfiguration(
        current: nil,
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "ja")
    )

    #expect(next.source == Locale.Language(identifier: "en"))
    #expect(next.target == Locale.Language(identifier: "ja"))
}

/// 同じ言語の組でもう一度選んだ時は、言語の組はそのままで、ダウンロードを動かし直せるよう版 (version) の変わった設定を返すこと
@Test func nextLanguageDownloadConfigurationRestartsForSameLanguages() {
    let current = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "ja")
    )
    let next = nextLanguageDownloadConfiguration(
        current: current,
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "ja")
    )

    #expect(next.version != current.version)
    #expect(next.source == Locale.Language(identifier: "en"))
    #expect(next.target == Locale.Language(identifier: "ja"))
}

/// 違う言語の組で選び直した時は、前の言語の組を引き継がず、新しい言語の組の設定を返すこと
@Test func nextLanguageDownloadConfigurationSwitchesToNewLanguages() {
    let next = nextLanguageDownloadConfiguration(
        current: TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "ja")
        ),
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "ko")
    )

    #expect(next.source == Locale.Language(identifier: "en"))
    #expect(next.target == Locale.Language(identifier: "ko"))
}
