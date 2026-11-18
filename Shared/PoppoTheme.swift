import SwiftUI
import UIKit

// 本体アプリとキーボードの見た目 (色・角の丸さ・ボタンの形) の定義。両方がこの 1 か所を使う。
// 方向は「少し可愛くて明るいが、仕事のチャットの返信に使う道具として可愛すぎない」(documents/DIRECTION.md「デザインの方向」)。
// 文字の色と地の色の組は、ライトとダークの両方でコントラスト比 4.5 以上にしてある (PoppoTests/PoppoThemeTests.swift が確かめる)

/// ライトの表示とダークの表示で値が変わる色を作って返す。
/// lightHex はライトの表示の色、darkHex はダークの表示の色で、どちらも 0xRRGGBB の形
nonisolated func poppoDynamicColor(lightHex: UInt32, darkHex: UInt32) -> UIColor {
    UIColor { traitCollection in
        poppoOpaqueColor(hex: traitCollection.userInterfaceStyle == .dark ? darkHex : lightHex)
    }
}

/// 0xRRGGBB の形の hex から、透明でない色を作って返す
nonisolated func poppoOpaqueColor(hex: UInt32) -> UIColor {
    UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

extension UIColor {
    /// 画面の地の色。ライトは少し黄みのある白で、標準の白より柔らかく見せる
    static let poppoBackground = poppoDynamicColor(lightHex: 0xFFF9EF, darkHex: 0x141C1B)
    /// 地の上に置くカード (発言の翻訳・返信案・説明の行) の色
    static let poppoSurface = poppoDynamicColor(lightHex: 0xFFFFFF, darkHex: 0x202B29)
    /// 押せるもの (ボタン・返信案の文) と、アプリの印になる色。アイコンの地の色と同じ色合いの青緑
    static let poppoAccent = poppoDynamicColor(lightHex: 0x0A6B5C, darkHex: 0x5FD6C2)
    /// poppoAccent で塗ったボタンの上に置く文字の色
    static let poppoOnAccent = poppoDynamicColor(lightHex: 0xFFFFFF, darkHex: 0x0B2F2A)
    /// 主な文 (発言の翻訳・返信案の意味の上に来る文・見出し) の色
    static let poppoPrimaryText = poppoDynamicColor(lightHex: 0x1D2624, darkHex: 0xF1F5F4)
    /// 補助の文 (原文・返信案の意味・説明) の色
    static let poppoSecondaryText = poppoDynamicColor(lightHex: 0x5F6B68, darkHex: 0xA7B5B1)
    /// エラーを伝える文と、取り込み中の印・停止のボタンの色。意味を持つ色で、飾りには使わない
    static let poppoError = poppoDynamicColor(lightHex: 0xC5281C, darkHex: 0xFF7B6E)
    /// poppoError で塗ったボタンの上に置く文字の色
    static let poppoOnError = poppoDynamicColor(lightHex: 0xFFFFFF, darkHex: 0x3A0A06)
    /// 読んでから時間が経った読み取り結果の印の色。意味を持つ色で、飾りには使わない
    static let poppoStale = poppoDynamicColor(lightHex: 0x8A4700, darkHex: 0xFFB35C)
    /// 鳥の絵の後ろに置く丸い地の色。アイコンの地 (scripts/render-app-icon.sh) と同じ値で、ライトとダークで変えない
    /// (鳥の体が白いため、明るい地の上にそのまま置くと形が見えない)
    static let poppoBirdBackground = poppoOpaqueColor(hex: 0x2BB5A0)
}

extension ShapeStyle where Self == Color {
    /// 画面の地の色
    static var poppoBackground: Color { Color(uiColor: .poppoBackground) }
    /// 地の上に置くカードの色
    static var poppoSurface: Color { Color(uiColor: .poppoSurface) }
    /// 押せるものと、アプリの印になる色
    static var poppoAccent: Color { Color(uiColor: .poppoAccent) }
    /// poppoAccent で塗ったボタンの上に置く文字の色
    static var poppoOnAccent: Color { Color(uiColor: .poppoOnAccent) }
    /// 主な文の色
    static var poppoPrimaryText: Color { Color(uiColor: .poppoPrimaryText) }
    /// 補助の文の色
    static var poppoSecondaryText: Color { Color(uiColor: .poppoSecondaryText) }
    /// エラーを伝える文と、取り込み中の印・停止のボタンの色
    static var poppoError: Color { Color(uiColor: .poppoError) }
    /// poppoError で塗ったボタンの上に置く文字の色
    static var poppoOnError: Color { Color(uiColor: .poppoOnError) }
    /// 読んでから時間が経った読み取り結果の印の色
    static var poppoStale: Color { Color(uiColor: .poppoStale) }
    /// 鳥の絵の後ろに置く丸い地の色
    static var poppoBirdBackground: Color { Color(uiColor: .poppoBirdBackground) }
}

/// カード (発言の翻訳・返信案・説明の行) の角の丸さ。
/// 16: 標準の一覧の行 (10 前後) より丸くして柔らかく見せつつ、2 行の文を入れたカードが丸薬の形に見えない大きさ
let poppoCardCornerRadius: CGFloat = 16

/// 小さい部品 (スクリーンショットの縮小画像・キーボードを切り替えるキー) の角の丸さ。
/// 12: 幅が 44〜120pt の部品で、カード (16) と同じ丸みに見える比率にした
let poppoSmallCornerRadius: CGFloat = 12

/// PoppoTintedButtonStyle がボタンを塗る時の、poppoAccent の不透明度。
/// 0.14: 地の色がほぼ透けて、その上の文字 (poppoAccent) がコントラスト比 4.5 以上を保つ薄さ (PoppoThemeTests が確かめる)
let poppoTintedFillOpacity: CGFloat = 0.14

/// 画面で最も勧める操作のボタンの形。丸い端の帯を fill の色で塗り、その上の文字を label の色で出す
struct PoppoFilledButtonStyle: ButtonStyle {
    /// ボタンを塗る色
    let fill: Color
    /// ボタンの上の文字の色
    let label: Color

    /// ボタンの中身 (configuration.label) を、塗った丸い端の帯の上に置いた見た目にして返す。押している間は薄くする
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(label)
            .padding(.horizontal, 20)
            // 13: 文字の高さ (約 22pt) と合わせてボタンの高さが 48pt 前後になり、指で押す最小の大きさ (44pt) を下回らない
            .padding(.vertical, 13)
            .background(fill, in: .capsule)
            // 0.7: 押している間だけ薄くして、押せたことを伝える
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 勧める操作の次に置く操作のボタンの形。丸い端の帯を poppoAccent の薄い色で塗り、文字を poppoAccent で出す
struct PoppoTintedButtonStyle: ButtonStyle {
    /// ボタンの中身 (configuration.label) を、薄く塗った丸い端の帯の上に置いた見た目にして返す。押している間は薄くする
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.poppoAccent)
            .padding(.horizontal, 20)
            // 13: PoppoFilledButtonStyle と同じ高さにそろえる
            .padding(.vertical, 13)
            .background(Color.poppoAccent.opacity(poppoTintedFillOpacity), in: .capsule)
            // 0.7: 押している間だけ薄くして、押せたことを伝える
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// 画面全体に Poppo の見た目 (丸い書体・押せるものの色・主な文の色) を当てる。本体アプリとキーボードの根で 1 回ずつ呼ぶ
    func poppoThemed() -> some View {
        fontDesign(.rounded)
            .tint(.poppoAccent)
            .foregroundStyle(.poppoPrimaryText)
    }

    /// 画面いっぱいに広げて、地の色 (poppoBackground) を敷く。一覧 (List) に付けた時は、一覧の標準の地を消して同じ色を見せる
    func poppoScreenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .background(.poppoBackground)
    }

    /// 地の上に置くカードの形 (poppoSurface の地と poppoCardCornerRadius の角) にする
    func poppoCard() -> some View {
        background(.poppoSurface, in: .rect(cornerRadius: poppoCardCornerRadius))
    }
}
