import { test } from 'node:test';
import assert from 'node:assert/strict';
import { StatusSnapshotGate, toggleDisabled } from '../src/run-state.ts';
const ready = { running: false, completed_cycles: 0, error: null, shortcut_error: null };
test('starting requires a confirmed emergency shortcut and an idle UI', () => {
  assert.equal(toggleDisabled(ready, false, false, false), true);
  assert.equal(toggleDisabled({ ...ready, shortcut_error: 'Wayland shortcut unavailable' }, true, false, false), true);
  assert.equal(toggleDisabled(ready, true, true, false), true);
  assert.equal(toggleDisabled(ready, true, false, true), true);
  assert.equal(toggleDisabled(ready, true, false, false), false);
});
test('stopping remains available during a run even if other state changes', () => {
  assert.equal(toggleDisabled({ ...ready, running: true, shortcut_error: 'lost' }, false, true, true), false);
});

test('an event received while fetching a snapshot prevents stale state from replacing it', () => {
  const gate = new StatusSnapshotGate();
  const checkpoint = gate.checkpoint();
  gate.eventReceived();
  assert.equal(gate.canApply(checkpoint), false);
  assert.equal(gate.canApply(gate.checkpoint()), true);
});
