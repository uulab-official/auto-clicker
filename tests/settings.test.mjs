import { test } from 'node:test';
import assert from 'node:assert/strict';
import { defaults, parseSettings, parseBackup, serializeBackup, MAX_BACKUP_BYTES } from '../src/settings.ts';

test('valid settings are restored including multi-monitor coordinates', () => {
  const value = defaults(); value.mode = 'sequence'; value.steps = [{ kind: 'click', button: 'right', clicks: 2, position: { x: -1200, y: 300 }, interval_ms: 50 }, { kind: 'wait', duration_ms: 250 }]; value.repeat = 3;
  assert.deepEqual(parseSettings(JSON.stringify(value)), value);
});
test('old settings migrate without losing the configured sequence', () => {
  const old = defaults(); old.repeat = 4; delete old.startDelayMs;
  assert.deepEqual(parseSettings(JSON.stringify(old)), { ...old, startDelayMs: 0 });
  assert.equal(parseSettings(JSON.stringify({ ...defaults(), startDelayMs: 5000 })).startDelayMs, 5000);
  assert.deepEqual(parseSettings(JSON.stringify({ ...defaults(), startDelayMs: 61000 })), defaults());
});
test('corrupted or partially shaped storage falls back to usable defaults', () => {
  for (const raw of ['{', 'null', JSON.stringify({ ...defaults(), steps: [null] }), JSON.stringify({ ...defaults(), simple: { kind: 'click' } }), JSON.stringify({ ...defaults(), repeat: 0 }), JSON.stringify({ ...defaults(), steps: Array(1001).fill({kind:'wait', duration_ms:1}) })]) assert.deepEqual(parseSettings(raw), defaults());
});
test('backups round trip complex and empty sequences', () => {
  const value = defaults(); value.mode = 'sequence'; value.steps = [{kind:'click', button:'middle', clicks:2, position:{x:-100,y:22}, interval_ms:20}, {kind:'wait', duration_ms:500}]; value.repeat = 4; value.startDelayMs = 3000;
  assert.deepEqual(parseBackup(serializeBackup(value)), value);
  value.steps = [];
  assert.deepEqual(parseBackup(serializeBackup(value)), value);
});
test('backup accepts prior settings while rejecting damaged and future formats', () => {
  const legacy = defaults(); delete legacy.startDelayMs;
  assert.deepEqual(parseBackup(JSON.stringify(legacy)), { ...legacy, startDelayMs: 0 });
  for (const value of ['{', 'null', JSON.stringify({ format:'auto-clicker-settings', version:2, settings:defaults() }), JSON.stringify({...defaults(), repeat:0}), JSON.stringify({...defaults(), steps:[null]}), ' '.repeat(MAX_BACKUP_BYTES + 1)]) {
    assert.throws(() => parseBackup(value));
  }
});
