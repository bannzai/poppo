import { anthropic } from '@genkit-ai/anthropic';
import { openAI } from '@genkit-ai/compat-oai/openai';
import { googleAI } from '@genkit-ai/google-genai';
import type { ModelArgument, z } from 'genkit';
import type { ReplyProviderSchema } from './generateReplyTextsFlow.js';

/**
 * 提供元から、その提供元で返信の文を作るモデルを返す。
 * モデルは、各 plugin の文書に載っているモデルのうち小さい側を仮に選んだ (試す間の費用を 3 社それぞれ 10 ドルに収めるため。
 * documents/DIRECTION.md「決めたこと」の 2026-11-20 の行)。質を比べて決め直す (documents/adr/0003-serve-off-device-reply-models-through-genkit-server.md「owner が決めること」)
 */
export function modelOfProvider(provider: z.infer<typeof ReplyProviderSchema>): ModelArgument {
  switch (provider) {
    case 'claude':
      return anthropic.model('claude-haiku-4-5');
    case 'openAI':
      // strict は、出力を schema のとおりに OpenAI の側で絞る指定
      // (「Set `strict: true` to have OpenAI enforce your output schema exactly」 https://genkit.dev/docs/integrations/openai/ )
      return openAI.model('gpt-5.4-mini', { strict: true });
    case 'gemini':
      return googleAI.model('gemini-3.5-flash-lite');
  }
}
