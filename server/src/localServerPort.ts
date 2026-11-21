/**
 * 環境変数 PORT の値 (無ければ undefined) から、手元のサーバーが待ち受ける port を返す。
 * 無い時は 3400 (Genkit の `startFlowServer` の既定と同じ番号。Genkit の文書の例の URL をそのまま使えるようにするため)。
 * 0 は、空いている番号を OS に選ばせる指定としてそのまま返す。
 * 0 から 65535 の整数として読めない値 (空文字・数字でない文字を含む値・範囲の外) の時は失敗する
 * (読めない値を既定の番号に置き換えて、指定と違う番号で黙って待ち受けないため)
 */
export function localServerPort(portEnvironmentValue: string | undefined): number {
  if (portEnvironmentValue === undefined) {
    return 3400;
  }
  if (!/^\d+$/.test(portEnvironmentValue) || Number(portEnvironmentValue) > 65535) {
    throw new Error(`PORT must be an integer from 0 to 65535, but was "${portEnvironmentValue}".`);
  }
  return Number(portEnvironmentValue);
}
