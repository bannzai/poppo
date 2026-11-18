import Testing
import UIKit
@testable import Poppo

/// 色の sRGB の 1 成分 (0〜1) を、相対輝度の計算に使う線形の値にして返す (WCAG 2 の relative luminance の定義)
private func linearComponent(component: CGFloat) -> CGFloat {
    component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
}

/// 透明でない色の相対輝度 (0〜1) を返す (WCAG 2 の relative luminance の定義)
private func relativeLuminance(color: UIColor) -> CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: nil)
    return 0.2126 * linearComponent(component: red)
        + 0.7152 * linearComponent(component: green)
        + 0.0722 * linearComponent(component: blue)
}

/// 2 つの透明でない色のコントラスト比 (1〜21) を返す (WCAG 2 の contrast ratio の定義)
private func contrastRatio(foreground: UIColor, background: UIColor) -> CGFloat {
    let luminances = [relativeLuminance(color: foreground), relativeLuminance(color: background)]
    return (luminances.max()! + 0.05) / (luminances.min()! + 0.05)
}

/// background の上に、overlay を不透明度 opacity で重ねた時に見える色を返す
private func blended(overlay: UIColor, opacity: CGFloat, background: UIColor) -> UIColor {
    var overlayRed: CGFloat = 0
    var overlayGreen: CGFloat = 0
    var overlayBlue: CGFloat = 0
    overlay.getRed(&overlayRed, green: &overlayGreen, blue: &overlayBlue, alpha: nil)
    var backgroundRed: CGFloat = 0
    var backgroundGreen: CGFloat = 0
    var backgroundBlue: CGFloat = 0
    background.getRed(&backgroundRed, green: &backgroundGreen, blue: &backgroundBlue, alpha: nil)
    return UIColor(
        red: overlayRed * opacity + backgroundRed * (1 - opacity),
        green: overlayGreen * opacity + backgroundGreen * (1 - opacity),
        blue: overlayBlue * opacity + backgroundBlue * (1 - opacity),
        alpha: 1
    )
}

/// 画面で実際に重なる、文字の色と地の色の組
private let textAndBackgroundPairs: [(name: String, text: UIColor, background: UIColor)] = [
    ("主な文と画面の地", .poppoPrimaryText, .poppoBackground),
    ("主な文とカード", .poppoPrimaryText, .poppoSurface),
    ("補助の文と画面の地", .poppoSecondaryText, .poppoBackground),
    ("補助の文とカード", .poppoSecondaryText, .poppoSurface),
    ("押せる文と画面の地", .poppoAccent, .poppoBackground),
    ("押せる文とカード", .poppoAccent, .poppoSurface),
    ("塗ったボタンの文字とボタン", .poppoOnAccent, .poppoAccent),
    ("エラーの文と画面の地", .poppoError, .poppoBackground),
    ("エラーの文とカード", .poppoError, .poppoSurface),
    ("停止のボタンの文字とボタン", .poppoOnError, .poppoError),
    ("古い読み取り結果の印と画面の地", .poppoStale, .poppoBackground),
]

/// 表示の種類 (ライトとダーク)
private let userInterfaceStyles: [UIUserInterfaceStyle] = [.light, .dark]

struct PoppoThemeTests {
    // 引数で組ごとのテストに分けない。テストの引数の式は MainActor の外で評価され、MainActor に属する色の定義を読めないため
    @Test
    func textHasEnoughContrastWithItsBackground() {
        for userInterfaceStyle in userInterfaceStyles {
            let traitCollection = UITraitCollection(userInterfaceStyle: userInterfaceStyle)
            for pair in textAndBackgroundPairs {
                // 4.5: WCAG 2 の達成基準 1.4.3 (AA) が、通常の大きさの文字に求めるコントラスト比
                #expect(
                    contrastRatio(
                        foreground: pair.text.resolvedColor(with: traitCollection),
                        background: pair.background.resolvedColor(with: traitCollection)
                    ) >= 4.5,
                    "\(pair.name) (\(userInterfaceStyle == .dark ? "ダーク" : "ライト"))"
                )
            }
        }
    }

    @Test
    func tintedButtonLabelHasEnoughContrastWithItsFill() {
        for userInterfaceStyle in userInterfaceStyles {
            let traitCollection = UITraitCollection(userInterfaceStyle: userInterfaceStyle)
            // 薄く塗ったボタンは、画面の地の上に置く (取り込みを始める入口)
            #expect(
                contrastRatio(
                    foreground: UIColor.poppoAccent.resolvedColor(with: traitCollection),
                    background: blended(
                        overlay: UIColor.poppoAccent.resolvedColor(with: traitCollection),
                        opacity: poppoTintedFillOpacity,
                        background: UIColor.poppoBackground.resolvedColor(with: traitCollection)
                    )
                ) >= 4.5,
                "\(userInterfaceStyle == .dark ? "ダーク" : "ライト")"
            )
        }
    }

    @Test
    func contrastRatioOfBlackAndWhiteIsTwentyOne() {
        #expect(abs(contrastRatio(foreground: .black, background: .white) - 21) < 0.01)
    }

    @Test
    func hexIsSplitIntoRedGreenBlue() {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        poppoOpaqueColor(hex: 0xFF8000).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(red == 1)
        #expect(abs(green - 128.0 / 255.0) < 0.001)
        #expect(blue == 0)
        #expect(alpha == 1)
    }

    @Test
    func dynamicColorSwitchesBetweenLightAndDark() {
        #expect(
            relativeLuminance(
                color: poppoDynamicColor(lightHex: 0xFFFFFF, darkHex: 0x000000)
                    .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            ) == 1
        )
        #expect(
            relativeLuminance(
                color: poppoDynamicColor(lightHex: 0xFFFFFF, darkHex: 0x000000)
                    .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            ) == 0
        )
    }
}
