import { test } from 'node:test';
import assert from 'node:assert/strict';
import { translate } from '../src/i18n.ts';
test('language fallback and dynamic user-visible text', () => {
  assert.equal(translate('Start clicking', 'en'), 'Start clicking');
  assert.equal(translate('Start clicking', 'ko'), '클릭 시작');
  assert.equal(translate('Completed cycles: 3', 'ja'), '完了した回数: 3');
  assert.equal(translate('Fixed position · -1200, 300', 'ko'), '고정 위치 · -1200, 300');
  assert.equal(translate('Duplicate step 3', 'en'), 'Duplicate step 3');
  assert.equal(translate('Duplicate step 3', 'ko'), '3단계 복제');
  assert.equal(translate('Duplicate step 3', 'ja'), 'ステップ3を複製');
  assert.match(translate('On some Mac keyboards, hold Fn or Globe with F8 to use it as a function key.', 'ko'), /Fn/);
  assert.match(translate('On some Mac keyboards, hold Fn or Globe with F8 to use it as a function key.', 'ja'), /Fn/);
  assert.notEqual(translate('Some emergency shortcuts are unavailable. Use an available shortcut shown below.', 'ko'), 'Some emergency shortcuts are unavailable. Use an available shortcut shown below.');
  assert.notEqual(translate('Clicking is paused while the pointer is over this window. Move it to where you want to click.', 'ko'), 'Clicking is paused while the pointer is over this window. Move it to where you want to click.');
  assert.match(translate('Could not capture the pointer position: denied', 'ja'), /denied/);
});
