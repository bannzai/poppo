import type { z } from 'genkit';
import type { ReplyProviderSchema } from '../src/generateReplyTextsFlow.js';

/** 返信の文を作るモデルの候補 1 つ。単価は Standard の料金で、100 万トークンあたりの USD */
export type CandidateReplyModel = {
  /** モデルの提供元 */
  provider: z.infer<typeof ReplyProviderSchema>;
  /** 提供元の API でのモデルの ID */
  modelName: string;
  /**
   * OpenAI の strict の指定 (出力を schema のとおりに OpenAI の側で絞る。サーバーの src/providerModels.ts と同じ指定) を付けて呼ぶか。
   * OpenAI のほかの提供元では false。OpenAI でも、plugin (@genkit-ai/compat-oai 1.44.0) の一覧 (lib/openai/gpt.js) に無いモデルは
   * strict を付けると提供元を呼ぶ前に失敗する (2026-11-22 の実測: gpt-6-luna で
   * 「OpenAI strict output requires output.format="json" and an output schema.」) ため false にして、出力の形を指示の文だけで伝える
   */
  usesStrictOutput: boolean;
  /** 入力の単価 */
  inputUSDPerMillionTokens: number;
  /** 出力の単価 (思考のトークンにも同じ単価がかかる) */
  outputUSDPerMillionTokens: number;
};

/**
 * 比べる候補のモデル。提供元ごとに、今サーバーかアプリが使っているモデルと、それより安いモデル・1 段上のモデルを入れる。
 * 単価と廃止の予定は 2026-11-22 に次のページで読んだ (廃止の予定が入っているモデルは候補に入れていない)。
 * - Claude: https://platform.claude.com/docs/en/about-claude/pricing 、 https://platform.claude.com/docs/en/about-claude/model-deprecations
 * - OpenAI: https://developers.openai.com/api/docs/pricing 、 https://developers.openai.com/api/docs/deprecations
 * - Gemini: https://aistudio.google.com/docs/pricing 、 https://aistudio.google.com/docs/deprecations
 * 単価が変わった時は、ここの値を直してから測り直す (費用はここの単価と、実際に返ったトークンの数から計算する)
 */
export const candidateReplyModels: CandidateReplyModel[] = [
  // サーバーが今使っている (料金の表の ID は claude-haiku-4-5-20251001)
  { provider: 'claude', modelName: 'claude-haiku-4-5', usesStrictOutput: false, inputUSDPerMillionTokens: 1, outputUSDPerMillionTokens: 5 },
  // 単価は入力が 10 万トークン以下の時のもの (会話の文は数百トークン)
  { provider: 'claude', modelName: 'claude-haiku-5-5', usesStrictOutput: false, inputUSDPerMillionTokens: 0.1, outputUSDPerMillionTokens: 0.5 },
  { provider: 'claude', modelName: 'claude-sonnet-5-5', usesStrictOutput: false, inputUSDPerMillionTokens: 2, outputUSDPerMillionTokens: 10 },
  // アプリの開発者メニューが今使っている
  { provider: 'openAI', modelName: 'gpt-6-luna', usesStrictOutput: false, inputUSDPerMillionTokens: 0.1, outputUSDPerMillionTokens: 0.5 },
  { provider: 'openAI', modelName: 'gpt-5.6-luna', usesStrictOutput: true, inputUSDPerMillionTokens: 0.2, outputUSDPerMillionTokens: 1.2 },
  // サーバーが今使っている
  { provider: 'openAI', modelName: 'gpt-5.4-mini', usesStrictOutput: true, inputUSDPerMillionTokens: 0.75, outputUSDPerMillionTokens: 4.5 },
  { provider: 'openAI', modelName: 'gpt-6.1-terra', usesStrictOutput: false, inputUSDPerMillionTokens: 1, outputUSDPerMillionTokens: 5 },
  { provider: 'gemini', modelName: 'gemini-2.5-flash-lite', usesStrictOutput: false, inputUSDPerMillionTokens: 0.1, outputUSDPerMillionTokens: 0.4 },
  // サーバーとアプリの開発者メニューが今使っている
  { provider: 'gemini', modelName: 'gemini-3.5-flash-lite', usesStrictOutput: false, inputUSDPerMillionTokens: 0.3, outputUSDPerMillionTokens: 2.5 },
  // 単価は 2026-12-31 までのもの (2027-01-01 から入力 1.50・出力 7.50 になると料金の表にある)
  { provider: 'gemini', modelName: 'gemini-3.8-flash', usesStrictOutput: false, inputUSDPerMillionTokens: 0.75, outputUSDPerMillionTokens: 3.75 },
];
