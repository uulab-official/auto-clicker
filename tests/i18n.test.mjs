import { test } from 'node:test';
import assert from 'node:assert/strict';
import { translate } from '../src/i18n.ts';
test('language fallback and dynamic user-visible text', () => {
  assert.equal(translate('Start clicking', 'en'), 'Start clicking');
  assert.equal(translate('Start clicking', 'ko'), '클릭 시작');
  assert.equal(translate('Completed cycles: 3', 'ja'), '完了した回数: 3');
  assert.equal(translate('Fixed position · -1200, 300', 'ko'), '고정 위치 · -1200, 300');
  assert.match(translate('Could not capture the pointer position: denied', 'ja'), /denied/);
});
