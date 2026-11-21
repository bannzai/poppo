/**
 * createPlugin のそれぞれで plugin を作り、作れたものだけを、渡された順で返す。
 * 作る時に失敗した createPlugin は、失敗の文を onFailure に渡して除く。
 * API キーが無い提供元の plugin は作る時に失敗するものがある (API キー無しの起動の実測: `anthropic()` が
 * 「Please pass in the API key or set the ANTHROPIC_API_KEY environment variable」で失敗した) ため、
 * キーを 1 社分しか持たない時も、その提供元だけで起動できるようにする
 */
export function createUsablePlugins<Plugin>(createPlugins: (() => Plugin)[], onFailure: (message: string) => void): Plugin[] {
  return createPlugins.flatMap((createPlugin) => {
    try {
      return [createPlugin()];
    } catch (error) {
      onFailure(error instanceof Error ? error.message : String(error));
      return [];
    }
  });
}
