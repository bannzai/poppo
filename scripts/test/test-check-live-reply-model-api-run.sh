#!/usr/bin/env bash
# scripts/check-live-reply-model-api-run.sh のテスト。キーの有無と、xcodebuild のログを模した入力で、検査の合否を確かめる。
# Usage: bash scripts/test/test-check-live-reply-model-api-run.sh
# 一時ディレクトリだけに書き、何度実行しても同じ結果になる
set -uo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-live-reply-model-api-run.sh"
work="$(mktemp -d)"
pass=0
fail=0

# 期待する exit code を、実際の結果と比べる。3 つ目以降は実行するコマンド
expect_code() {
  local description="$1" expected_code="$2"
  shift 2
  "$@" > /dev/null 2> "$work/stderr"
  local code=$?
  if [ "$code" -eq "$expected_code" ]; then
    echo "PASS: $description"
    pass=$((pass + 1))
  else
    echo "FAIL: ${description} (exit=${code} / 期待は exit=${expected_code})"
    fail=$((fail + 1))
  fi
}

# 直前の実行の標準エラーが、文字列を含む・含まないことを確かめる
expect_stderr() {
  local description="$1" mode="$2" text="$3"
  if { [ "$mode" = contains ] && grep -q -- "$text" "$work/stderr"; } || { [ "$mode" = lacks ] && ! grep -q -- "$text" "$work/stderr"; }; then
    echo "PASS: $description"
    pass=$((pass + 1))
  else
    echo "FAIL: ${description} (標準エラー: $(cat "$work/stderr"))"
    fail=$((fail + 1))
  fi
}

expect_code "両方のキーがあれば通る" 0 env TEST_RUNNER_OPENAI_API_KEY=key-a TEST_RUNNER_GEMINI_API_KEY=key-b bash "$script" keys
expect_code "OpenAI のキーだけでは通らない" 1 env -u TEST_RUNNER_GEMINI_API_KEY TEST_RUNNER_OPENAI_API_KEY=key-a bash "$script" keys
expect_stderr "足りない名前 (GEMINI_API_KEY) を出す" contains "GEMINI_API_KEY"
expect_stderr "ある方の名前 (OPENAI_API_KEY) は出さない" lacks "OPENAI_API_KEY"
expect_stderr "キーの値を出さない" lacks "key-a"
expect_code "Gemini のキーだけでは通らない" 1 env -u TEST_RUNNER_OPENAI_API_KEY TEST_RUNNER_GEMINI_API_KEY=key-b bash "$script" keys
expect_stderr "足りない名前 (OPENAI_API_KEY) を出す" contains "OPENAI_API_KEY"
expect_code "片方が空文字なら通らない (登録していない Secret は空文字で渡る)" 1 env TEST_RUNNER_OPENAI_API_KEY=key-a TEST_RUNNER_GEMINI_API_KEY= bash "$script" keys
expect_code "両方とも無ければ通らない" 1 env -u TEST_RUNNER_OPENAI_API_KEY -u TEST_RUNNER_GEMINI_API_KEY bash "$script" keys

# 通った行と落ちた行の形は、実際の実行のログから写した (返信の文のテストが通った行は、同じ実行の別のテストの通った行の名前と秒数を変えたもの。https://github.com/bannzai/poppo/pull/70 の本文の「workflow が使う仕組みの実測」)
cat > "$work/passed.log" <<'EOF'
✔ Test realAPIReturnsThreeReplyTexts(replyModel:) with 2 test cases passed after 4.210 seconds.
✔ Test wrongAPIKeyThrowsClientErrorStatusWithoutAPIKey(replyModel:) with 2 test cases passed after 3.149 seconds.
✔ Test run with 2 tests in 1 suite passed after 7.936 seconds.
EOF
expect_code "返信の文のテストが通ったログは通る" 0 bash "$script" log "$work/passed.log"

cat > "$work/failed.log" <<'EOF'
✘ Test realAPIReturnsThreeReplyTexts(replyModel:) recorded an issue with 1 argument replyModel → .gemini at LiveReplyModelAPITests.swift:55:6: Caught error: .unexpectedStatus(statusCode: Optional(400))
✘ Test realAPIReturnsThreeReplyTexts(replyModel:) with 2 test cases failed after 0.783 seconds with 2 issues.
✔ Test wrongAPIKeyThrowsClientErrorStatusWithoutAPIKey(replyModel:) with 2 test cases passed after 3.149 seconds.
✘ Test run with 2 tests in 1 suite failed after 3.936 seconds with 2 issues.
EOF
expect_code "返信の文のテストが落ちたログは通らない (別のテストが通っていても)" 1 bash "$script" log "$work/failed.log"

# 飛ばされた時のログは実際の実行から写したものではない (通った行が無いログの見本)
cat > "$work/skipped.log" <<'EOF'
➜ Suite LiveReplyModelAPITests skipped
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
** TEST SUCCEEDED **
EOF
expect_code "suite が飛ばされてテストが動かなかったログは通らない" 1 bash "$script" log "$work/skipped.log"

: > "$work/empty.log"
expect_code "空のログは通らない" 1 bash "$script" log "$work/empty.log"
expect_code "ログのファイルが無ければ引数の誤り" 2 bash "$script" log "$work/missing.log"
expect_code "サブコマンドが無ければ引数の誤り" 2 bash "$script"

echo "PASS=${pass} FAIL=${fail}"
[ "$fail" -eq 0 ]
