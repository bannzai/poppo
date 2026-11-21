import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { replyInstructions, replyTextsDescription } from '../src/generateReplyTextsFlow.js';

/** アプリが返信の文を作る処理のソース。モデルへの指示の文の正 */
const replyGenerationSwift = readFileSync(new URL('../../Poppo/ChatReading/ReplyGeneration.swift', import.meta.url), 'utf8');

/**
 * Swift のソースから、name という名前の定数に入れた複数行の文字列リテラルの値を返す。
 * 扱うのは、閉じる `"""` の字下げを各行から除くことと、行末の `\` (改行を入れずに次の行へ続ける) だけ。
 * 見つからない時は失敗する
 */
function swiftMultilineStringLiteral(source: string, name: string): string {
  const match = source.match(new RegExp(`let ${name} = """\\n([\\s\\S]*?)\\n( *)"""`));
  assert.ok(match, `${name} が見つからない`);
  return match[1]
    .split('\n')
    .map((line) => line.slice(match[2].length))
    .join('\n')
    .replaceAll('\\\n', '');
}

test('モデルへの指示の文が、アプリの replyInstructions と同じ文である', () => {
  assert.equal(replyInstructions, swiftMultilineStringLiteral(replyGenerationSwift, 'replyInstructions'));
});

test('返信の文の組の説明の文が、アプリの GeneratedReplyTexts.texts の @Guide の説明と同じ文である', () => {
  assert.equal(replyTextsDescription, replyGenerationSwift.match(/@Guide\(description: "(.*)", \.count\(3\)\)/)?.[1]);
});
