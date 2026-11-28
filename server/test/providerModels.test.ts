import assert from 'node:assert/strict';
import { test } from 'node:test';
import { modelOfProvider } from '../src/providerModels.js';

for (const [provider, name, config] of [
  ['claude', 'anthropic/claude-haiku-4-5', {}],
  // 設定が無い (strict の指定を付けない)。付けると plugin が提供元を呼ぶ前に失敗する
  ['openAI', 'openai/gpt-6-luna', undefined],
  ['gemini', 'googleai/gemini-3.5-flash-lite', {}],
] as const) {
  test(`${provider} には ${name} を、設定 ${JSON.stringify(config)} で使う`, () => {
    const model = modelOfProvider(provider);

    assert.ok(typeof model === 'object' && 'name' in model);
    assert.equal(model.name, name);
    assert.deepEqual(model.config, config);
  });
}
