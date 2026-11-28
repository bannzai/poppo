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
  'Write every reply in the same language as the "Them:" lines. ' +
  "The replies are suggestions on the person's keyboard: tapping one sends it exactly as written. " +
  'Yes-or-no questions, including whether the person is free or willing, are decided by the person choosing a reply, ' +
  'so offer both answers. ' +
  'For anything else that only the person knows, do not write it or a blank for it; ' +
  'the person will type it themselves, so suggest replies that work without it.';

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
 * text の中の JSON が、閉じないまま text の終わりに達しているかを返す (JSON が無い時と、閉じている時は false)。
 * Genkit は閉じていない JSON を補って読む (genkit 1.44.0 の実測: `{"texts":["Yes, I am.","Sorry, I am busy.","What ti` が
 * 3 つ目を「What ti」とした 3 つの文として schema を通った) ため、出力の上限などで切れた文を返信の文として返さないように確かめる。
 * JSON の始まりと終わりは、Genkit が output を読む時と同じ選び方で探す (`@genkit-ai/ai` 1.44.0 の `extractJson`:
 * `"` で囲まれていない最初の `{` か `[` から、同じ種類の括弧が閉じる所まで。`"` の中の括弧と `\` の次の 1 文字は数えない)。
 * 選び方を変えると、Genkit が補って読んだ JSON とは別の括弧を見て閉じていると判断してしまう
 * (例: `Example "{}". {"texts":["Yes.","No.","What ti`)
 */
function endsInsideUnclosedJSON(text: string): boolean {
  let openingBracket: '{' | '[' | undefined;
  let nestingCount = 0;
  let isInsideString = false;
  let isEscaped = false;
  for (const character of text) {
    if (isEscaped) {
      isEscaped = false;
    } else if (character === '\\') {
      isEscaped = true;
    } else if (character === '"') {
      isInsideString = !isInsideString;
    } else if (isInsideString) {
      continue;
    } else if (openingBracket === undefined && (character === '{' || character === '[')) {
      openingBracket = character;
      nestingCount = 1;
    } else if (character === openingBracket) {
      nestingCount += 1;
    } else if (character === (openingBracket === '{' ? '}' : ']') && openingBracket !== undefined) {
      nestingCount -= 1;
      if (nestingCount === 0) {
        return false;
      }
    }
  }
  return openingBracket !== undefined;
}

/**
 * model に会話の文を渡し、会話に続けて利用者が送れる返信の文 3 つ (`texts`) と、その呼び出しで数えられたトークンの数 (`usage`) を返す。
 * 提供元の API を 1 回呼ぶ (利用料がかかる)。モデルの出力が返信の文 3 つの形でない時は失敗する (一部だけを返さない)。
 * abortSignal を渡すと、その signal が止めた時に呼び出しを打ち切って失敗する (渡さない時は打ち切らない)。
 * instructions はモデルへの指示の文で、渡さない時は `replyInstructions`
 * (指示の文を変える前と後を比べる測定だけが、ほかの文を渡す。server/README.md「指示の文を変える前と後を比べる」)
 */
export async function generateReplyTextsWithModel(
  ai: Genkit,
  model: ModelArgument,
  conversation: string,
  abortSignal?: AbortSignal,
  instructions: string = replyInstructions,
) {
  const { output, text, usage } = await ai.generate({
    model,
    system: instructions,
    prompt: conversation,
    output: { schema: GeneratedReplyTextsSchema },
    abortSignal,
  });
  // 出力が schema に合わない時、output は null になる
  // (「the `output` property can be `null`」「when the model fails to generate output that conforms to the schema」 https://genkit.dev/docs/models/ )
  // 文に JSON が無い時 (出力が文でない部分 (data) で届いた時。説明の文が付いていてもよい) は、切れた文を補って読んだ出力ではないので通す
  if (output === null || endsInsideUnclosedJSON(text)) {
    throw new GenkitError({ status: 'INTERNAL', message: 'The model did not return three reply texts.' });
  }
  return { texts: output.texts, usage };
}

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
    async ({ conversation, provider }) => ({
      texts: (await generateReplyTextsWithModel(ai, modelOfProvider(provider), conversation)).texts,
    }),
  );
}
