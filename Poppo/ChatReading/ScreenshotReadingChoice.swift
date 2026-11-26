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

/// 行から、画面の上部 (ナビゲーションバー) に出ているチャットの名前を読んで返す。読めない時は nil
nonisolated func chatTitleReadFromScreen(lines: [RecognizedTextLine]) -> String? {
    // 0.06: ステータスバー (時刻・電波・電池) の文字をチャットの名前にしないため、行の上下の中心がこれより下の行だけを見る。
    // ステータスバーの高さは Dynamic Island のある iPhone で 54pt (画面の高さ 874pt の 6.2%)、ノッチの iPhone で 47pt (844pt の 5.6%) で、
    // 文字の中心はその半分ほどの所に来る。見本の画像 (PoppoTests/ChatScreenSamples/) ではステータスバーの文字の中心が 3.3%、チャットの名前の中心が 8.8% にある
    lines
        .filter { $0.boundingBox.midY >= 0.06 && $0.boundingBox.minY < chatAreaTopEdge && !isTimeOnly(text: $0.text) }
        // 戻るボタンの「‹」や未読の数より、チャットの名前の方が長いため、最も長い行を名前とする
        .max { $0.text.count < $1.text.count }
        .map(\.text)
        .flatMap { comparableClueText(text: $0).isEmpty ? nil : $0 }
}

/// 発言から、見出し行 (先頭の行で、名前の後に時刻が並ぶ行) の名前を読んで、画面の上から下の順に返す。同じ名前は 1 つにまとめる。
/// 見出し行の無い発言 (吹き出しのチャット) からは読まない。時刻の前に「hoy a las」のような語が付く画面では、その語も名前に含めて返す
nonisolated func speakerNames(messages: [ExtractedMessage]) -> [String] {
    messages
        .compactMap { message in
            message.text.split(separator: "\n").first.flatMap {
                String($0).firstMatch(of: #/^(?<name>.+?)\s+((午前|午後)\s?)?\d{1,2}:\d{2}(\s?[AaPp][Mm])?$/#).map { String($0.name) }
            }
        }
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
/// 似ている記録が複数ある時は、チャットの名前が同じものを、その中でも発言した人の名前の重なりが大きいものを、それも同じなら新しいものを返す。
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
/// チャットの名前が同じ時は 2 以上、発言した人の名前だけで似ている時は 1 以下にする (名前が同じ記録を先に選ぶため)
private nonisolated func clueSimilarity(chatTitles: (String?, String?), speakerNames: ([String], [String])) -> Double? {
    let namesOverlap = speakerNamesOverlap(speakerNames: speakerNames)
    switch (chatTitles.0.map { comparableClueText(text: $0) }, chatTitles.1.map { comparableClueText(text: $0) }) {
    case (let newTitle?, let pastTitle?):
        // 両方で名前を読めた時は名前で決める: 同じ人がいる別のチャンネルは別のチャットのため
        return newTitle == pastTitle ? 2 + namesOverlap : nil
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
        choices: (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([ScreenshotReadingChoice].self, from: $0) } ?? [],
        now: now
    )
}

/// 記録 (choices) を fileURL に保存する。前に保存した記録は上書きされる。書き込めない時はエラーを投げる
nonisolated func save(screenshotReadingChoices choices: [ScreenshotReadingChoice], fileURL: URL) throws {
    // atomic: 書いている途中で本体アプリが終了しても、前の記録を壊さないため
    try JSONEncoder().encode(choices).write(to: fileURL, options: .atomic)
}

/// スクリーンショットから読んだ行 (lines) の手がかりと、この読み取りの既定にする言語と関係を、新しい記録として fileURL に足して返す。
/// usesMostSimilarChoice が true で、過去の記録に手がかりが似ているもの (mostSimilarScreenshotReadingChoice) がある時は、その記録の言語と関係を既定にする。
/// 似ているものが無い時と、usesMostSimilarChoice が false の時 (利用者が既に選び直した時) は、今選ばれている言語と関係
/// (targetLanguageIdentifier・chatPartnerRelationship) を既定にする。
/// 足す時に、残す期間を過ぎた記録と上限を超えた記録を消す。保存できなかった時はエラーを投げる (既定は返さない)
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
    let names = speakerNames(messages: extractMessages(lines: lines))
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
    try save(screenshotReadingChoices: retainedScreenshotReadingChoices(choices: [newChoice] + pastChoices, now: now), fileURL: fileURL)
    return newChoice
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
