// swift-tools-version: 6.2
import PackageDescription

/// Claude をつなぐ package (ClaudeForFoundationModels) を、iOS 27 の SDK がある Xcode (Swift 6.4 以降) でだけ依存に入れるための package。
/// ClaudeForFoundationModels は iOS 27 の Foundation Models の型 (LanguageModel 等) を使うため、Xcode 26 ではコンパイルできない
/// (CodeQL の実測: https://github.com/bannzai/poppo/actions/runs/44881737135 の「cannot find type 'LanguageModel' in scope」)。
/// CodeQL の Swift の解析は Xcode 26 でアプリをビルドする (.github/workflows/codeql.yml) ため、本体アプリが直接依存すると解析が止まる。
/// Xcode のプロジェクトは依存を compiler の版で切り替えられないため、切り替えをこの manifest に置く
let package = Package(
    name: "PoppoClaude",
    // 本体アプリと同じ iOS 27 以降。.v27 の定数は tools-version 6.4 を求めるため、文字列で書く
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "PoppoClaude", targets: ["PoppoClaude"]),
    ],
    targets: [
        .target(name: "PoppoClaude"),
    ]
)

#if compiler(>=6.4)
package.dependencies.append(
    // Beta の package で版の間に互換性の保証が無いため、足した時点の最新 (2026-10-07 の release) に固定する
    .package(url: "https://github.com/anthropics/ClaudeForFoundationModels", exact: "0.2.3")
)
package.targets[0].dependencies.append(
    .product(name: "ClaudeForFoundationModels", package: "ClaudeForFoundationModels")
)
#endif
