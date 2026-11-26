import CoreGraphics
import Foundation

/// スクリーンショットからの読み取り 1 回の、チャットを見分ける手がかりと、その読み取りで選ばれていた訳す先の言語・相手との関係。
/// 後で同じ相手のスクリーンショットを読んだ時に、その時の言語と関係を既定にするため、本体アプリの中 (端末) にだけ置く (端末の外へ送らない)。
/// 読み取った時点 (documents/DIRECTION.md の「用語」) の一覧を作る時は、別の記録を作らず、この記録に画像や翻訳を足してその一覧の 1 件にする
nonisolated struct ScreenshotReadingChoice: Codable, Equatable, Identifiable, Sendable {
    /// 読み取りごとに振る識別子。利用者が読み取りの画面で選び直した時に、どの記録を書き換えるかを決めるのに使う
    let id: UUID
    /// スクリーンショットを読んだ時刻。似ている記録が複数ある時に新しい方を選ぶのと、残す期間を過ぎたかを見るのに使う
    let readAt: Date
    /// 画面の上部 (ナビゲーションバー) から読んだままのチャットの名前 (チャンネル名・相手の名前)。読めなかった時は nil
    let chatTitleReadFromScreen: String?
    /// 発言の見出し行 (名前と時刻が並ぶ行) から読んだままの、発言した人の名前。画面の上から下の順で、同じ名前は 1 つにまとめる
    let speakerNames: [String]
    /// この読み取りで選ばれていた訳す先の言語 (Locale.Language の maximalIdentifier)。何も選んでいない (端末の言語へ訳す) 時は nil
    var targetLanguageIdentifier: String?
    /// この読み取りで選ばれていた相手との関係。未選択の時は nil
    var chatPartnerRelationship: ChatPartnerRelationship?
}

/// 行から、画面の上部 (ナビゲーションバー) の左右の中央に出ているチャットの名前を読んで返す。
/// 中央に行が無い時 (名前を左に寄せて出すアプリ) は読まない (nil)。戻るボタンのラベル (「‹ Messages」) や右のボタンを名前にして、
/// 同じラベルを出す別の相手を同じチャットとみなさないため
nonisolated func chatTitleReadFromScreen(lines: [RecognizedTextLine]) -> String? {
    // 0.06: ステータスバー (時刻・電波・電池) の文字をチャットの名前にしないため、行の上下の中心がこれより下の行だけを見る。
    // ステータスバーの高さは Dynamic Island のある iPhone で 54pt (画面の高さ 874pt の 6.2%)、ノッチの iPhone で 47pt (844pt の 5.6%) で、
    // 文字の中心はその半分ほどの所に来る。見本の画像 (PoppoTests/ChatScreenSamples/) ではステータスバーの文字の中心が 3.3%、チャットの名前の中心が 8.8% にある
    lines
        .filter {
            $0.boundingBox.midY >= 0.06 && $0.boundingBox.minY < chatAreaTopEdge && !isTimeOnly(text: $0.text)
                // 0.15: ナビゲーションバーの題名は左右の中央に置かれ、行の枠の中心は幅によらず画面の中央に来る。
                // 左端の戻るボタン (中心は画面の幅の 2 割より左) と右端のボタン (8 割より右) を外し、枠のぶれを見込んで中央から 15% までを題名とみなす
                && abs($0.boundingBox.midX - 0.5) <= 0.15
                && !comparableClueText(text: $0.text).isEmpty
        }
        // 題名の下に小さく出る補助の行 (「オンライン」「3 人」) より、題名の方が上にあるため、最も上の行を名前とする
        .min { $0.boundingBox.minY < $1.boundingBox.minY }
        .map(\.text)
}

/// 行から、発言の見出し (名前と、そのすぐ右に別の行として並ぶ時刻) の名前を読んで、画面の上から下の順に返す。同じ名前は 1 つにまとめる。
/// 見出しとするのは、発言の並ぶ範囲の左寄りの行で、すぐ右に時刻で終わる行 (「10:42 AM」「hoy a las 18:05」) が並び、すぐ下に同じ左端の本文の行が続く行だけ。
/// 発言の本文を名前として残さないため、次の行は見出しにしない: 時刻で終わる 1 つの行 (「Meet me at 10:42」)、
/// 吹き出しの中で最後の行の右に時刻が付く行 (下に本文が続かない)、右に寄った利用者の発言の行。
/// 名前と時刻を Vision が 1 つの行として読んだ画面では、名前を読まない (本文の文と見分けられないため)
nonisolated func speakerNames(lines: [RecognizedTextLine]) -> [String] {
    let chatAreaLines = lines.filter { isInsideChatArea(line: $0) }
    return
        chatAreaLines
        .filter { nameLine in
            chatAreaLines.contains { timeLine in
                continuesRow(leftLine: nameLine, line: timeLine)
                    // 時刻の前の語は 3 語まで: 「hoy a las 18:05」のような時刻の書き方を通し、本文の文を時刻の行にしないため
                    && (0...3).contains { leadingWordCount in
                        isTimeOnly(text: timeLine.text.split(separator: " ").dropFirst(leadingWordCount).joined(separator: " "))
                    }
                    && !isShiftedRight(lines: [nameLine, timeLine])
            }
                && chatAreaLines.contains { bodyLine in
                    bodyLine.boundingBox.minY > nameLine.boundingBox.maxY && continuesMessage(previousLine: nameLine, line: bodyLine)
                }
        }
        .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        .map(\.text)
        .reduce(into: [String]()) { names, name in
            if !names.contains(where: { comparableClueText(text: $0) == comparableClueText(text: name) }) {
                names.append(name)
            }
        }
}

/// 手がかりの文字を、別のスクリーンショットから読んだ文字と比べられる形にして返す。文字と数字だけを残し、小文字にそろえる。
/// Vision が名前の間の空白を落とすことがあり (PoppoTests/ChatScreenSamples/chat-screen-samples.json の knownIssue)、
/// 戻るボタンの「‹」やチャンネルの「#」が名前と同じ行に読まれることがあるため
nonisolated func comparableClueText(text: String) -> String {
    String(text.lowercased().filter { $0.isLetter || $0.isNumber })
}

/// 新しく読んだスクリーンショットの手がかり (chatTitleReadFromScreen と speakerNames) に最も似ている過去の記録を pastChoices から返す。
/// 似ているとするのは次の時: 両方でチャットの名前を読めた時はその名前が同じ。どちらかで名前を読めなかった時は、発言した人の名前の半分以上が同じ。
/// 似ている記録が複数ある時は、チャットの名前が同じものの中で新しいものを返す。チャットの名前が同じものが無い時は、
/// 発言した人の名前の重なりが大きいものを、それも同じなら新しいものを返す。
/// チャットの名前が同じものどうしで重なりを比べないのは、同じチャットで利用者が最後に選んだ選択を既定にするため
/// (選び直した時に書き換わるのはその読み取りの記録だけで、同じチャットの古い記録は前の選択のまま残る)。
/// 似ている記録が無い時は nil
nonisolated func mostSimilarScreenshotReadingChoice(
    chatTitleReadFromScreen: String?,
    speakerNames: [String],
    pastChoices: [ScreenshotReadingChoice]
) -> ScreenshotReadingChoice? {
    pastChoices
        .compactMap { pastChoice in
            clueSimilarity(
                chatTitles: (chatTitleReadFromScreen, pastChoice.chatTitleReadFromScreen),
                speakerNames: (speakerNames, pastChoice.speakerNames)
            ).map { (pastChoice: pastChoice, similarity: $0) }
        }
        .max { ($0.similarity, $0.pastChoice.readAt) < ($1.similarity, $1.pastChoice.readAt) }?
        .pastChoice
}

/// 2 つの読み取りの手がかりがどれだけ似ているかを返す。大きいほど似ている。似ていない時は nil。
/// チャットの名前が同じ時はどれも 2 (同じ値にして新しさで選ぶ)、発言した人の名前だけで似ている時は 1 以下にする (名前が同じ記録を先に選ぶため)
private nonisolated func clueSimilarity(chatTitles: (String?, String?), speakerNames: ([String], [String])) -> Double? {
    let namesOverlap = speakerNamesOverlap(speakerNames: speakerNames)
    switch (chatTitles.0.map { comparableClueText(text: $0) }, chatTitles.1.map { comparableClueText(text: $0) }) {
    case (let newTitle?, let pastTitle?):
        // 両方で名前を読めた時は名前で決める: 同じ人がいる別のチャンネルは別のチャットのため
        return newTitle == pastTitle ? 2 : nil
    default:
        // 0.5: 片方だけに出ている人より、両方に出ている人の方が多い時に同じ相手とみなす。
        // 1 人だけが重なる別の会話 (自分の名前だけが同じ等) を同じ相手にしないため
        return namesOverlap >= 0.5 ? namesOverlap : nil
    }
}

/// 2 つの読み取りの、発言した人の名前の重なり (両方にいる人の数 ÷ どちらかにいる人の数)。どちらも名前が無い時は 0
private nonisolated func speakerNamesOverlap(speakerNames: ([String], [String])) -> Double {
    let newNames = Set(speakerNames.0.map { comparableClueText(text: $0) }.filter { !$0.isEmpty })
    let pastNames = Set(speakerNames.1.map { comparableClueText(text: $0) }.filter { !$0.isEmpty })
    let allNames = newNames.union(pastNames)
    return allNames.isEmpty ? 0 : Double(newNames.intersection(pastNames).count) / Double(allNames.count)
}

/// 残す記録だけを、新しい順に返す。読んでから 14 日を過ぎた記録と、新しい方から数えて 200 件より後の記録を除く
nonisolated func retainedScreenshotReadingChoices(choices: [ScreenshotReadingChoice], now: Date) -> [ScreenshotReadingChoice] {
    Array(
        choices
            // 14 日: 読み取った時点 (画面の画像と翻訳) を本体アプリの中に残す期間 (documents/DIRECTION.md「決めたこと」の 2026-11-19 の bannzai の行) と同じにする。
            // この記録は後でその一覧の 1 件になるため、残す期間をそろえる
            .filter { now.timeIntervalSince($0.readAt) < 14 * 24 * 60 * 60 }
            .sorted { $0.readAt > $1.readAt }
            // 200 件: 無料の利用者の読み取りの上限 (1 日 10 回。2026-11-19 の行) で 14 日に読める 140 件を残せる数。
            // 有料の利用者が多く読んだ時に、記録のファイルが大きくなり続けないための上限
            .prefix(200)
    )
}

/// スクリーンショットからの読み取りの記録を置くファイルの場所を返す。本体アプリの Application Support の中で、キーボードと共有する場所 (App Group) には置かない。
/// 場所を作れない時は nil を返す
func screenshotReadingChoicesFileURL() -> URL? {
    try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("screenshot-reading-choices.json")
}

/// fileURL に保存してある記録のうち、残す記録 (retainedScreenshotReadingChoices(choices:now:)) を新しい順に返す。
/// 保存していない時と、記録として読めない中身の時は空を返す
nonisolated func loadScreenshotReadingChoices(fileURL: URL, now: Date) -> [ScreenshotReadingChoice] {
    retainedScreenshotReadingChoices(
        // 空: 記録は既定を選ぶための手がかりで、読めない時は前に読んだ相手が無い時と同じに扱えば足りる (直前の選択が既定になる)。
        // 読めない中身は次に記録を足した時に上書きされる
        choices: (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([ScreenshotReadingChoice].self, from: $0) } ?? [],
        now: now
    )
}

/// 記録 (choices) を fileURL に保存し、そのファイルを端末のバックアップ (iCloud・パソコンへのバックアップ) から外す。
/// 前に保存した記録は上書きされる。書き込めない時はエラーを投げる。
/// バックアップから外せない時は、書いたファイルを消してからエラーを投げる (記録はすべて無くなる)
nonisolated func save(screenshotReadingChoices choices: [ScreenshotReadingChoice], fileURL: URL) throws {
    // atomic: 書いている途中で本体アプリが終了しても、前の記録を壊さないため
    try JSONEncoder().encode(choices).write(to: fileURL, options: .atomic)
    // バックアップから外す: 記録には相手の名前が入り、端末の外へ出さないと決めているため。Application Support はそのままではバックアップされる
    // (「the contents of the Library directory (with the exception of the Caches subdirectory) are backed up by iTunes and iCloud」
    // https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html )。
    // atomic の書き込みはファイルを置き換えるため、書くたびに付け直す
    do {
        try (fileURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    } catch {
        // 消す: バックアップに入りうるファイルを残さないため。記録は既定を選ぶ手がかりで、無くなっても直前の選択が既定になるだけで済む
        try? FileManager.default.removeItem(at: fileURL)
        throw error
    }
}

/// スクリーンショットから読んだ行 (lines) の手がかりと、この読み取りの既定にする言語と関係を、新しい記録として fileURL に足して返す。
/// usesMostSimilarChoice が true で、過去の記録に手がかりが似ているもの (mostSimilarScreenshotReadingChoice) がある時は、その記録の言語と関係を既定にする。
/// 似ているものが無い時と、usesMostSimilarChoice が false の時 (利用者が既に選び直した時) は、今選ばれている言語と関係
/// (targetLanguageIdentifier・chatPartnerRelationship) を既定にする。
/// 足す時に、残す期間を過ぎた記録と上限を超えた記録を消す。保存できなかった時はエラーを投げる (既定は返さない)。
/// チャットの名前も発言した人の名前も読めなかった時は、記録を足さずに (残す期間を過ぎた記録を消して保存し直し) 今の選択の記録を返す (どの記録とも似ているとしないため、
/// 残しても既定に使われず、200 件の枠を使って手がかりのある記録を押し出すだけのため)。返した記録は保存していないため、書き換えても何も起きない
nonisolated func addScreenshotReadingChoice(
    lines: [RecognizedTextLine],
    targetLanguageIdentifier: String?,
    chatPartnerRelationship: ChatPartnerRelationship?,
    usesMostSimilarChoice: Bool,
    id: UUID,
    now: Date,
    fileURL: URL
) throws -> ScreenshotReadingChoice {
    let pastChoices = loadScreenshotReadingChoices(fileURL: fileURL, now: now)
    let chatTitle = chatTitleReadFromScreen(lines: lines)
    let names = speakerNames(lines: lines)
    // 似ている記録の言語と関係は、未選択 (nil) もそのまま既定にする (その相手では何も選んでいなかったため)
    let (defaultTargetLanguageIdentifier, defaultChatPartnerRelationship) =
        (usesMostSimilarChoice
        ? mostSimilarScreenshotReadingChoice(chatTitleReadFromScreen: chatTitle, speakerNames: names, pastChoices: pastChoices)
        : nil)
        .map { ($0.targetLanguageIdentifier, $0.chatPartnerRelationship) } ?? (targetLanguageIdentifier, chatPartnerRelationship)
    let newChoice = ScreenshotReadingChoice(
        id: id,
        readAt: now,
        chatTitleReadFromScreen: chatTitle,
        speakerNames: names,
        targetLanguageIdentifier: defaultTargetLanguageIdentifier,
        chatPartnerRelationship: defaultChatPartnerRelationship
    )
    // 手がかりが無い時も保存し直す: 残す期間を過ぎた記録をファイルから消すため (プライバシーポリシーの「次に読み取った時に削除」)
    try save(
        screenshotReadingChoices: retainedScreenshotReadingChoices(
            choices: (chatTitle != nil || !names.isEmpty ? [newChoice] : []) + pastChoices,
            now: now
        ),
        fileURL: fileURL
    )
    return newChoice
}

/// 読み取りの画面が文字を読み終えた時に、読み取りを記録し、その画面で既定にする記録 (言語と関係) と、読み取りを始め直すかを返す。
/// fileURL が nil (記録の場所を作れない) の時と、記録を保存できなかった時は、記録 nil と「始め直さない」を返す (今の選択のまま読む。既定を選べないだけで翻訳と返信案は出せるため)。
/// hasUserChangedChoice が true (利用者がこの画面で既に選び直した) の時は、過去の記録を当てない。
/// 始め直すのは、記録の言語と関係が今の選択 (savedTargetLanguageIdentifier は端末に保存してある書き方のまま。未選択は空文字) と違い、
/// 読み取りのタスクの id が変わる時 (defaultChoiceRestartsChatReading)
func recordScreenshotReading(
    lines: [RecognizedTextLine],
    savedTargetLanguageIdentifier: String,
    chatPartnerRelationship: ChatPartnerRelationship?,
    hasUserChangedChoice: Bool,
    preferredLanguages: [String],
    id: UUID,
    now: Date,
    fileURL: URL?
) -> (choice: ScreenshotReadingChoice?, restartsReading: Bool) {
    guard
        let choice = fileURL.flatMap({
            try? addScreenshotReadingChoice(
                lines: lines,
                targetLanguageIdentifier: recordedTargetLanguageIdentifier(savedIdentifier: savedTargetLanguageIdentifier),
                chatPartnerRelationship: chatPartnerRelationship,
                usesMostSimilarChoice: !hasUserChangedChoice,
                id: id,
                now: now,
                fileURL: $0
            )
        })
    else {
        return (choice: nil, restartsReading: false)
    }
    return (
        choice: choice,
        restartsReading: defaultChoiceRestartsChatReading(
            defaultChoice: choice,
            savedTargetLanguageIdentifier: savedTargetLanguageIdentifier,
            chatPartnerRelationship: chatPartnerRelationship,
            preferredLanguages: preferredLanguages
        )
    )
}

/// fileURL の記録のうち id の記録の言語と関係を、利用者が選び直した targetLanguageIdentifier・chatPartnerRelationship に書き換える
/// (次に同じ相手を読んだ時の既定にするため)。その記録が無い時 (残す期間を過ぎて消えた時) は何もしない。保存できなかった時はエラーを投げる
nonisolated func updateScreenshotReadingChoice(
    id: UUID,
    targetLanguageIdentifier: String?,
    chatPartnerRelationship: ChatPartnerRelationship?,
    now: Date,
    fileURL: URL
) throws {
    let choices = loadScreenshotReadingChoices(fileURL: fileURL, now: now)
    guard choices.contains(where: { $0.id == id }) else {
        return
    }
    try save(
        screenshotReadingChoices: choices.map { choice in
            guard choice.id == id else {
                return choice
            }
            var updatedChoice = choice
            updatedChoice.targetLanguageIdentifier = targetLanguageIdentifier
            updatedChoice.chatPartnerRelationship = chatPartnerRelationship
            return updatedChoice
        },
        fileURL: fileURL
    )
}
