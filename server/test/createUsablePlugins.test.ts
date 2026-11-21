import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createUsablePlugins } from '../src/createUsablePlugins.js';

/** 作る時に message の文で失敗する plugin の作り手 */
function failing(message: string): () => string {
  return () => {
    throw new Error(message);
  };
}

test('どれも作れた時は、全部を渡された順で返し、失敗を伝えない', () => {
  const failureMessages: string[] = [];

  assert.deepEqual(
    createUsablePlugins([() => 'a', () => 'b', () => 'c'], (message) => failureMessages.push(message)),
    ['a', 'b', 'c'],
  );
  assert.deepEqual(failureMessages, []);
});

test('作る時に失敗したものだけを除き、残りを順のまま返して、失敗の文を伝える', () => {
  const failureMessages: string[] = [];

  assert.deepEqual(
    createUsablePlugins([failing('no key for a'), () => 'b', failing('no key for c'), () => 'd'], (message) => failureMessages.push(message)),
    ['b', 'd'],
  );
  assert.deepEqual(failureMessages, ['no key for a', 'no key for c']);
});

test('全部が失敗した時は、失敗せずに空の配列を返す', () => {
  const failureMessages: string[] = [];

  assert.deepEqual(
    createUsablePlugins([failing('x'), failing('y')], (message) => failureMessages.push(message)),
    [],
  );
  assert.deepEqual(failureMessages, ['x', 'y']);
});

test('Error でない値で失敗した時は、その値を文字列にして伝える', () => {
  const failureMessages: string[] = [];

  createUsablePlugins(
    [
      () => {
        throw 'plain text';
      },
    ],
    (message) => failureMessages.push(message),
  );

  assert.deepEqual(failureMessages, ['plain text']);
});
