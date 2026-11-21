import { anthropic } from '@genkit-ai/anthropic';
import { openAI } from '@genkit-ai/compat-oai/openai';
import { googleAI } from '@genkit-ai/google-genai';
import { genkit } from 'genkit';
import { createUsablePlugins } from './createUsablePlugins.js';
import { defineGenerateReplyTextsFlow } from './generateReplyTextsFlow.js';
import { startLocalFlowServer } from './localFlowServer.js';
import { modelOfProvider } from './providerModels.js';

// 手元で試すための起動口。このマシンの中からだけ届く (127.0.0.1)。
// 各提供元の API キーは、plugin が環境変数 (ANTHROPIC_API_KEY・OPENAI_API_KEY・GEMINI_API_KEY) から読む。
// plugin を作れなかった提供元を指定した呼び出しは失敗する
// PORT が無い時の 3400 は、Genkit の `startFlowServer` の既定と同じ番号 (Genkit の文書の例の URL をそのまま使えるようにするため)
const port = Number.parseInt(process.env.PORT ?? '3400');
await startLocalFlowServer(
  defineGenerateReplyTextsFlow(
    genkit({
      plugins: createUsablePlugins([() => anthropic(), () => openAI(), () => googleAI()], (message) =>
        console.warn(`plugin を 1 つ使わずに起動する: ${message}`),
      ),
    }),
    modelOfProvider,
  ),
  port,
);
console.log(`http://127.0.0.1:${port}/generateReplyTexts で待ち受けている`);
