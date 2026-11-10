import { test } from 'node:test';
import assert from 'node:assert/strict';
import { defaults, parseSettings } from '../src/settings.ts';

test('valid settings are restored including multi-monitor coordinates', () => {
  const value = defaults(); value.mode = 'sequence'; value.steps = [{ kind: 'click', button: 'right', clicks: 2, position: { x: -1200, y: 300 }, interval_ms: 50 }, { kind: 'wait', duration_ms: 250 }]; value.repeat = 3;
  assert.deepEqual(parseSettings(JSON.stringify(value)), value);
});
test('corrupted or partially shaped storage falls back to usable defaults', () => {
  for (const raw of ['{', 'null', JSON.stringify({ ...defaults(), steps: [null] }), JSON.stringify({ ...defaults(), simple: { kind: 'click' } }), JSON.stringify({ ...defaults(), repeat: 0 }), JSON.stringify({ ...defaults(), steps: Array(1001).fill({kind:'wait', duration_ms:1}) })]) assert.deepEqual(parseSettings(raw), defaults());
});
