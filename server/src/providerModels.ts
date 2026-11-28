import { anthropic } from '@genkit-ai/anthropic';
import { openAI } from '@genkit-ai/compat-oai/openai';
import { googleAI } from '@genkit-ai/google-genai';
import type { ModelArgument, z } from 'genkit';
import type { ReplyProviderSchema } from './generateReplyTextsFlow.js';

/**
 * 提供元から、その提供元で返信の文を作るモデルを返す。
 * OpenAI のモデルは、同じ会話の見本で測った結果から owner が決めた (documents/evaluation/2026-11-22-reply-model-benchmark.md。
 * documents/DIRECTION.md「決めたこと」の 2026-11-28 の行)。Claude と Gemini は、各 plugin の文書に載っているモデルのうち小さい側を
 * 仮に選んだまま (documents/adr/0003-serve-off-device-reply-models-through-genkit-server.md「owner が決めること」)
 */
export function modelOfProvider(provider: z.infer<typeof ReplyProviderSchema>): ModelArgument {
  switch (provider) {
    case 'claude':
      return anthropic.model('claude-haiku-4-5');
    case 'openAI':
      // strict (出力を schema のとおりに OpenAI の側で絞る指定) は付けない。plugin (@genkit-ai/compat-oai 1.44.0) の一覧に gpt-6-luna が無く、
      // 付けると提供元を呼ぶ前に失敗する (2026-11-22 の実測:「OpenAI strict output requires output.format="json" and an output schema.」)。
      // 付けなくても 24 回中 24 回、返信の文 3 つの形で返り、形の合わない出力は generateReplyTextsWithModel が失敗にする
      return openAI.model('gpt-6-luna');
    case 'gemini':
      return googleAI.model('gemini-3.5-flash-lite');
  }
}
