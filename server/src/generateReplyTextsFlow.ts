import { GenkitError, z, type Genkit, type ModelArgument } from 'genkit';

/**
 * 返信の文を作るモデルへの指示の文。どの提供元でも同じ文を使う。
 * 正はアプリの `replyInstructions` (`Poppo/ChatReading/ReplyGeneration.swift`) で、ここはその写し
 * (documents/adr/0003-serve-off-device-reply-models-through-genkit-server.md「指示の文の正」)。
 * 食い違いは test/replyInstructionsMatchApp.test.ts が検出する
 */
export const replyInstructions =
  'You help a person reply in a chat. The chat is listed from oldest to newest. ' +
  'Lines starting with "Me:" were written by the person you help. ' +
  'Lines starting with "Them:" were written by other people. ' +
  'Write replies that the person could send next in response to the latest "Them:" lines. ' +
  'Write every reply in the same language as the "Them:" lines.';

/**
 * 返信の文の組 (`texts`) がどういうものかをモデルに伝える説明の文。
 * 正はアプリの `GeneratedReplyTexts.texts` の `@Guide` の説明で、ここはその写し。
 * 食い違いは test/replyInstructionsMatchApp.test.ts が検出する
 */
export const replyTextsDescription = 'Three short replies the person could send next. Each reply differs in content or tone';

/** 返信の文を作るモデルの提供元 */
export const ReplyProviderSchema = z.enum(['claude', 'openAI', 'gemini']);

/** 返信の文を作る flow が受け取るもの */
export const GenerateReplyTextsInputSchema = z.object({
  /**
   * 会話の文。アプリの `replyPrompt(messages:)` が作る形 (発言を古い順に並べ、
   * 利用者自身の発言に「Me:」、相手の発言に「Them:」を付けた文)。
   * 空白と改行のほかの文字を 1 つ以上含む (返信する相手の発言が無いままモデルを呼んで利用料をかけないため)
   */
  conversation: z.string().regex(/\S/),
  /** 返信の文を作るモデルの提供元 */
  provider: ReplyProviderSchema,
});

/**
 * モデルに書かせる返信の文の組。アプリの `GeneratedReplyTexts` と同じ形。
 * `.strict()` は、OpenAI の strict の指定が object ごとに `additionalProperties: false` を求めるため
 * (「OpenAI's strict mode requires `additionalProperties: false` on every object, and Genkit does not add it for you」
 * https://genkit.dev/docs/integrations/openai/ )
 */
export const GeneratedReplyTextsSchema = z
  .object({
    /** 返信の文。3 つにする理由はアプリの `GeneratedReplyTexts.texts` と同じ */
    texts: z.array(z.string()).length(3).describe(replyTextsDescription),
  })
  .strict();

/**
 * 会話の文と提供元を受け取り、会話に続けて利用者が送れる返信の文 3 つを返す flow を ai に登録して返す。
 * modelOfProvider は提供元から、その提供元で使うモデルを返す (テストでは提供元の API を呼ばないモデルに差し替える)。
 * モデルの出力が返信の文 3 つの形でない時、flow は失敗する (一部だけを返さない)。
 * 冪等ではない: 同じ ai に 2 回呼ぶと、同じ名前の flow を登録し直す。ai ごとに 1 回だけ呼ぶ
 */
export function defineGenerateReplyTextsFlow(
  ai: Genkit,
  modelOfProvider: (provider: z.infer<typeof ReplyProviderSchema>) => ModelArgument,
) {
  return ai.defineFlow(
    {
      name: 'generateReplyTexts',
      inputSchema: GenerateReplyTextsInputSchema,
      outputSchema: GeneratedReplyTextsSchema,
    },
    async ({ conversation, provider }) => {
      const { output } = await ai.generate({
        model: modelOfProvider(provider),
        system: replyInstructions,
        prompt: conversation,
        output: { schema: GeneratedReplyTextsSchema },
      });
      // 出力が schema に合わない時、output は null になる
      // (「the `output` property can be `null`」「when the model fails to generate output that conforms to the schema」 https://genkit.dev/docs/models/ )
      if (output === null) {
        throw new GenkitError({ status: 'INTERNAL', message: 'The model did not return three reply texts.' });
      }
      return output;
    },
  );
}
