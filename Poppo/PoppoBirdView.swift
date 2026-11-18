import SwiftUI

/// アイコンと同じ鳥の絵を、アイコンと同じ色の丸い地の上に置いたもの。本体アプリの、中身がまだ無い場面の案内に置く。
/// 飾りのため、読み上げの対象にしない
struct PoppoBirdView: View {
    var body: some View {
        Image("PoppoBird")
            .resizable()
            .scaledToFit()
            // 12: 尾羽とくちばしが丸い地の縁に触れない余白
            .padding(12)
            // 104: 案内の見出し (title3) の上に置いて、絵が見出しより目立ちすぎず、目とくちばしが見分けられる大きさ
            .frame(width: 104, height: 104)
            .background(.poppoBirdBackground, in: .circle)
            .accessibilityHidden(true)
    }
}

/// 中身がまだ無い場面の案内。鳥の絵・見出し・説明・操作を縦に並べて、画面の中央に出す
struct PoppoEmptyStateView<Actions: View>: View {
    /// 見出し
    let title: Text
    /// 見出しの下に出す説明
    let description: Text
    /// 説明の下に出す操作。無い時は EmptyView を渡す
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            PoppoBirdView()
            VStack(spacing: 8) {
                title
                    .font(.title3.bold())
                description
                    .font(.subheadline)
                    .foregroundStyle(.poppoSecondaryText)
            }
            .multilineTextAlignment(.center)
            actions()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
