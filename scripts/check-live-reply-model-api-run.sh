#!/usr/bin/env bash
# 実際の API を呼ぶテスト (.github/workflows/verify-reply-model-apis.yml) の、実行の前と後の検査。
# テストが 1 つも動かないまま workflow が成功になるのを防ぐ。
#
# Usage:
#   bash scripts/check-live-reply-model-api-run.sh keys
#     環境変数 TEST_RUNNER_OPENAI_API_KEY と TEST_RUNNER_GEMINI_API_KEY の両方が空でないことを確かめる
#     (テストは両方がある時だけ動く。登録していない Secret は空文字で渡る)
#   bash scripts/check-live-reply-model-api-run.sh log <xcodebuild のログのファイル>
#     ログに、返信の文を 3 つ受け取るテスト (realAPIReturnsThreeReplyTexts) が通った行があることを確かめる
#
# exit code: 0 = 検査を通った / 1 = 通らなかった (理由を標準エラーに出す) / 2 = 引数の誤り
# キーの値は出力しない。状態を読むだけで、何度実行しても同じ結果になる
set -uo pipefail

case "${1:-}" in
  keys)
    missing=""
    [ -n "${TEST_RUNNER_OPENAI_API_KEY:-}" ] || missing="${missing} OPENAI_API_KEY"
    [ -n "${TEST_RUNNER_GEMINI_API_KEY:-}" ] || missing="${missing} GEMINI_API_KEY"
    if [ -n "$missing" ]; then
      echo "::error::Secrets が空です:${missing} (テストが動かずに成功になるため中止します)" >&2
      exit 1
    fi
    ;;
  log)
    [ -n "${2:-}" ] && [ -f "$2" ] || { echo "Usage: $0 log <ログのファイル>" >&2; exit 2; }
    # Swift Testing は、引数つきのテストが全部通った時だけ「✔ Test <名前>(...) with <n> test cases passed」の行を出す
    # (1 件でも落ちると同じ行が failed になる。実測: https://github.com/bannzai/poppo/pull/70 の本文の「workflow が使う仕組みの実測」)
    if ! grep -q 'Test realAPIReturnsThreeReplyTexts(.*passed' "$2"; then
      echo "::error::実際の API を呼ぶテストが通った記録がログにありません" >&2
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 keys | log <ログのファイル>" >&2
    exit 2
    ;;
esac
