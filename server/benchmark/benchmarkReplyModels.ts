import { writeFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import { anthropic } from '@genkit-ai/anthropic';
import { openAI } from '@genkit-ai/compat-oai/openai';
import { googleAI } from '@genkit-ai/google-genai';
import { genkit, type ModelArgument } from 'genkit';
import { generateReplyTextsWithModel } from '../src/generateReplyTextsFlow.js';
import {
  measureReplyModelCall,
  planReplyModelCalls,
  renderReplyTexts,
  renderSummaryTable,
  summarizeReplyModelCalls,
  type ReplyModelCall,
} from './benchmarkMeasures.js';
import { candidateReplyModels, type CandidateReplyModel } from './candidateReplyModels.js';
import { conversationSamples } from './conversationSamples.js';

// 候補のモデルを、同じ会話の見本で実際に呼んで比べる。提供元の API を呼ぶため利用料がかかる。
// 使い方と、結果の読み方は server/README.md「モデルを比べる」

/** 提供元ごとの、API キーを渡す環境変数の名前 (各 plugin が読む名前。server/README.md「手元での起動」と同じ) と、plugin とモデルの作り方 */
const providers = {
  claude: {
    apiKeyEnvironmentName: 'ANTHROPIC_API_KEY',
    createPlugin: () => anthropic(),
    model: (candidate: CandidateReplyModel): ModelArgument => anthropic.model(candidate.modelName),
  },
  openAI: {
    apiKeyEnvironmentName: 'OPENAI_API_KEY',
    createPlugin: () => openAI(),
    model: (candidate: CandidateReplyModel): ModelArgument => openAI.model(candidate.modelName, { strict: candidate.usesStrictOutput }),
  },
  gemini: {
    apiKeyEnvironmentName: 'GEMINI_API_KEY',
    createPlugin: () => googleAI(),
    model: (candidate: CandidateReplyModel): ModelArgument => googleAI.model(candidate.modelName),
  },
};

/**
 * 1 回の実行で呼んでよい回数の上限。候補 10 個 × 見本 8 つ × 3 回 = 240 回に余裕を足した数で、
 * 引数の指定を誤っても試す間の費用 (3 社それぞれ月 10 ドル。documents/DIRECTION.md「決めたこと」の 2026-11-21 の行) を大きく使わないようにする
 */
const maximumCallCount = 300;

/**
 * 1 回の呼び出しを待つ上限 (ミリ秒)。キーボードに返信案を出す用途で 1 分かかるモデルは候補にならないため、そこで打ち切って失敗に数える
 */
const callTimeoutMilliseconds = 60_000;

const { values: options } = parseArgs({
  options: {
    // 見本 1 つあたりの呼ぶ回数。3 は、中央値と最も遅い値を見本 8 つ × 3 回 = 24 回から出すための数
    runs: { type: 'string', default: '3' },
    // 測るモデルの名前 (カンマ区切り)。指定しない時は候補の全部
    models: { type: 'string' },
    // 全部の呼び出しの結果を JSON で書き出すファイル。指定しない時は書き出さない
    output: { type: 'string' },
  },
});

const { runCount, selectedModels, measuredModels } = planReplyModelCalls({
  candidates: candidateReplyModels,
  runs: options.runs,
  modelNames: options.models,
  sampleCount: conversationSamples.length,
  maximumCallCount,
  hasAPIKey: (model) => Boolean(process.env[providers[model.provider].apiKeyEnvironmentName]),
});

const ai = genkit({
  plugins: [...new Set(measuredModels.map((model) => model.provider))].map((provider) => providers[provider].createPlugin()),
});

// 違うモデルは並べて呼び、同じモデルの呼び出しは 1 つずつ順に呼ぶ (同じモデルを重ねて呼ぶと、返るまでの時間が提供元の側の混み具合で変わるため)
const calls = (
  await Promise.all(
    measuredModels.map(async (model) => {
      const modelCalls: ReplyModelCall[] = [];
      for (const sample of conversationSamples) {
        for (let runNumber = 1; runNumber <= runCount; runNumber += 1) {
          modelCalls.push(
            await measureReplyModelCall({ modelName: model.modelName, sampleID: sample.id, runNumber }, () =>
              generateReplyTextsWithModel(
                ai,
                providers[model.provider].model(model),
                sample.conversation,
                AbortSignal.timeout(callTimeoutMilliseconds),
              ),
            ),
          );
        }
      }
      return modelCalls;
    }),
  )
).flat();

console.log(
  [
    `測った日時: ${new Date().toISOString()} (見本 ${conversationSamples.length} つ × ${runCount} 回)`,
    '',
    renderSummaryTable(
      measuredModels.map((model) =>
        summarizeReplyModelCalls(
          model,
          calls,
          Object.fromEntries(conversationSamples.map((sample) => [sample.id, sample.themWritingScript])),
        ),
      ),
    ),
    '',
    ...selectedModels
      .filter((model) => !measuredModels.includes(model))
      .map((model) => `測っていない: \`${model.modelName}\` (環境変数 ${providers[model.provider].apiKeyEnvironmentName} が無い)`),
    '',
    renderReplyTexts(
      conversationSamples.map((sample) => sample.id),
      measuredModels.map((model) => model.modelName),
      calls,
    ),
  ].join('\n'),
);

// 表を出した後に書き出す (書き出しに失敗しても、利用料を払って測った結果が標準出力に残るようにするため)
if (options.output !== undefined) {
  await writeFile(options.output, `${JSON.stringify(calls, null, 2)}\n`);
}
