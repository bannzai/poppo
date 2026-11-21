import assert from 'node:assert/strict';
import { test } from 'node:test';
import { modelOfProvider } from '../src/providerModels.js';

for (const [provider, name, config] of [
  ['claude', 'anthropic/claude-haiku-4-5', {}],
  ['openAI', 'openai/gpt-5.4-mini', { strict: true }],
  ['gemini', 'googleai/gemini-3.5-flash-lite', {}],
] as const) {
  test(`${provider} には ${name} を、設定 ${JSON.stringify(config)} で使う`, () => {
    const model = modelOfProvider(provider);

    assert.ok(typeof model === 'object' && 'name' in model);
    assert.equal(model.name, name);
    assert.deepEqual(model.config, config);
  });
}
