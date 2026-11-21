import assert from 'node:assert/strict';
import { test } from 'node:test';
import { localServerPort } from '../src/localServerPort.js';

test('PORT が無い時は 3400 を返す', () => {
  assert.equal(localServerPort(undefined), 3400);
});

for (const [value, port] of [
  ['0', 0],
  ['1', 1],
  ['3499', 3499],
  ['65535', 65535],
] as const) {
  test(`PORT が "${value}" の時は ${port} を返す`, () => {
    assert.equal(localServerPort(value), port);
  });
}

for (const value of ['', 'abc', '3400abc', '34.5', '-1', ' 3400', '65536', '1e3']) {
  test(`PORT が "${value}" の時は、既定の番号に置き換えずに失敗する`, () => {
    assert.throws(() => localServerPort(value), /PORT must be an integer from 0 to 65535/);
  });
}
