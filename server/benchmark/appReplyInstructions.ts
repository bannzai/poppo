import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

/** リポジトリの中での、アプリが返信の文を作る処理のソースのパス。モデルへの指示の文 (`replyInstructions`) の正 */
export const replyGenerationSwiftPath = 'Poppo/ChatReading/ReplyGeneration.swift';

/**
 * Swift のソースから、name という名前の定数に入れた複数行の文字列リテラルの値を返す。
 * 扱うのは、閉じる `"""` の字下げを各行から除くことと、行末の `\` (改行を入れずに次の行へ続ける) だけ。
 * 見つからない時は Error を投げる
 */
export function swiftMultilineStringLiteral(source: string, name: string): string {
  const match = source.match(new RegExp(`let ${name} = """\\n([\\s\\S]*?)\\n( *)"""`));
  if (match === null) {
    throw new Error(`${name} が見つからない`);
  }
  return match[1]
    .split('\n')
    .map((line) => line.slice(match[2].length))
    .join('\n')
    .replaceAll('\\\n', '');
}

/**
 * git の gitRef (ブランチ・タグ・コミット) の時点の、アプリの `replyInstructions` の文を返す。
 * 指示の文を変える前と後を、同じ会話の見本とモデルで比べる時に、変える前の文を取り出すために使う。
 * gitRef が無い時と、その時点のソースに `replyInstructions` が無い時は Error を投げる
 */
export function appReplyInstructionsAtGitRef(gitRef: string): string {
  return swiftMultilineStringLiteral(
    // --end-of-options は、gitRef が「-」で始まる時に git の引数として読まれないようにするため
    execFileSync('git', ['show', '--end-of-options', `${gitRef}:${replyGenerationSwiftPath}`], {
      cwd: fileURLToPath(new URL('../../', import.meta.url)),
      encoding: 'utf8',
      // git の失敗の文 (標準エラー) は、投げられる Error の文に入るので、ここでは端末に出さない
      stdio: ['ignore', 'pipe', 'pipe'],
    }),
    'replyInstructions',
  );
}
