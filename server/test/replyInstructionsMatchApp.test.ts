import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { appReplyInstructionsAtGitRef, replyGenerationSwiftPath, swiftMultilineStringLiteral } from '../benchmark/appReplyInstructions.js';
import { replyInstructions, replyTextsDescription } from '../src/generateReplyTextsFlow.js';

/** アプリが返信の文を作る処理のソース。モデルへの指示の文の正 */
const replyGenerationSwift = readFileSync(new URL(`../../${replyGenerationSwiftPath}`, import.meta.url), 'utf8');

test('モデルへの指示の文が、アプリの replyInstructions と同じ文である', () => {
  assert.equal(replyInstructions, swiftMultilineStringLiteral(replyGenerationSwift, 'replyInstructions'));
});

test('返信の文の組の説明の文が、アプリの GeneratedReplyTexts.texts の @Guide の説明と同じ文である', () => {
  assert.equal(replyTextsDescription, replyGenerationSwift.match(/@Guide\(description: "(.*)", \.count\(3\)\)/)?.[1]);
});

test('Swift の複数行の文字列リテラルは、字下げを除き、行末の \\ でつないだ行を 1 行にして読む', () => {
  assert.equal(
    swiftMultilineStringLiteral('let other = """\n    x\n    """\nlet text = """\n    first \\\n    second\n      third\n    """\n', 'text'),
    'first second\n  third',
  );
});

test('Swift のソースに、その名前の複数行の文字列リテラルが無い時は失敗する', () => {
  assert.throws(() => swiftMultilineStringLiteral('let text = "one line"', 'text'), /text が見つからない/);
});

test('git の ref の時点の指示の文は、その時点のアプリの replyInstructions (相手の発言への返信を求める文で始まる)', () => {
  assert.match(appReplyInstructionsAtGitRef('HEAD'), /^You help a person reply in a chat\. /);
});

test('git に無い ref の時点の指示の文は読めずに失敗する', () => {
  assert.throws(() => appReplyInstructionsAtGitRef('no-such-ref-for-reply-instructions'));
});

test('「-」で始まる ref は、git の引数として読まれない (--output= で始まる ref を渡しても、ファイルが書き出されずに失敗する)', () => {
  const directory = mkdtempSync(join(tmpdir(), 'reply-instructions-ref-'));
  // ref の後ろに「:<ソースのパス>」が付くため、引数として読まれた時に書き出される先のディレクトリを作っておく
  mkdirSync(join(directory, `out:${dirname(replyGenerationSwiftPath)}`), { recursive: true });
  assert.throws(() => appReplyInstructionsAtGitRef(`--output=${join(directory, 'out')}`));
  assert.equal(existsSync(join(directory, `out:${replyGenerationSwiftPath}`)), false);
});
