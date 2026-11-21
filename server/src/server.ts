import { anthropic } from '@genkit-ai/anthropic';
import { openAI } from '@genkit-ai/compat-oai/openai';
import { startFlowServer } from '@genkit-ai/express';
import { googleAI } from '@genkit-ai/google-genai';
import { genkit } from 'genkit';
import { defineGenerateReplyTextsFlow } from './generateReplyTextsFlow.js';
import { modelOfProvider } from './providerModels.js';

// 手元で試すための起動口。呼び出しの確かめ (認証・回数の制限) を持たないため、外から届く場所で動かさない。
// 各提供元の API キーは、plugin が環境変数 (ANTHROPIC_API_KEY・OPENAI_API_KEY・GEMINI_API_KEY) から読む。
// API キーが無い提供元の plugin は作る時に失敗するものがある (API キー無しの起動の実測: anthropic() が
// 「Please pass in the API key or set the ANTHROPIC_API_KEY environment variable」で失敗した) ため、
// 作れた plugin だけで起動し、キーを 1 社分しか持たない時もその提供元を試せるようにする。作れなかった提供元を指定した呼び出しは失敗する
startFlowServer({
  flows: [
    defineGenerateReplyTextsFlow(
      genkit({
        plugins: [anthropic, openAI, googleAI].flatMap((plugin) => {
          try {
            return [plugin()];
          } catch (error) {
            console.warn(`${plugin.name} の plugin を使わずに起動する: ${error instanceof Error ? error.message : error}`);
            return [];
          }
        }),
      }),
      modelOfProvider,
    ),
  ],
});
