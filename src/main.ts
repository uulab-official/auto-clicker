import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { open as openDialog, save as saveDialog } from '@tauri-apps/plugin-dialog';
import { open as openFile, writeTextFile } from '@tauri-apps/plugin-fs';
import './style.css';
import { translate, translateDom, type Language } from './i18n';
import { defaultClick, defaults, parseSettings, parseBackup, serializeBackup, MAX_BACKUP_BYTES, type Settings, type Click, type Step, type Position } from './settings';
import { StatusSnapshotGate, toggleDisabled, type Status } from './run-state';

const key = 'open-clicker-settings-v1';
let settings = defaults();
let language: Language = navigator.language.toLowerCase().startsWith('ko') ? 'ko' : navigator.language.toLowerCase().startsWith('ja') ? 'ja' : 'en';
try { const saved = localStorage.getItem('open-clicker-language'); if (saved === 'en' || saved === 'ko' || saved === 'ja') language = saved; } catch { /* use system language */ }
try { settings = parseSettings(localStorage.getItem(key)); } catch { /* start with defaults if storage is unavailable */ }
let status: Status = { running: false, completed_cycles: 0, error: null, shortcut_error: null, shortcut_warning: null, available_shortcuts: [] };
let statusReady = false;
let notice = '';
let capturing = false;
let fileBusy = false;
type UpdateInfo = { version: string; current_version: string; notes: string | null };
let updateInfo: UpdateInfo | null = null;
let updateState: 'idle' | 'checking' | 'available' | 'current' | 'installing' | 'installed' | 'error' = 'idle';
let updateError = '';
const app = document.querySelector<HTMLDivElement>('#app')!;
const escape = (s: unknown) => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
const checked = (v: boolean) => v ? ' checked' : '';
const disabled = (v: boolean) => v ? ' disabled' : '';
const isMac = /Mac/i.test(navigator.platform) || /Macintosh/i.test(navigator.userAgent);
function save() { try { localStorage.setItem(key, JSON.stringify(settings)); } catch { notice = 'Settings could not be saved on this device.'; } }
function options(selected: string, values: [string, string][]) { return values.map(([v, label]) => `<option value="${v}"${v === selected ? ' selected' : ''}>${label}</option>`).join(''); }
function clickFields(step: Click, index: string) {
  const position = step.position;
  return `<div class="field-grid">
    <label>Mouse button<select data-index="${index}" data-field="button">${options(step.button, [['left','Left'],['right','Right'],['middle','Middle']])}</select></label>
    <label>Click type<select data-index="${index}" data-field="clicks">${options(String(step.clicks), [['1','Single click'],['2','Double click']])}</select></label>
    <label>Interval <span class="unit">ms</span><input type="number" min="10" max="86400000" step="1" data-index="${index}" data-field="interval_ms" value="${escape(step.interval_ms)}" required></label>
  </div>
  <div class="location"><div><span class="label">Click location</span><p class="hint">${position ? `Fixed position · ${escape(position.x)}, ${escape(position.y)}` : 'Wherever the pointer is when the click happens'}</p></div>
    <div class="location-actions"><button type="button" class="button secondary small" data-action="capture" data-index="${index}"${disabled(capturing)}>Pick position</button>${position ? `<button type="button" class="button text small" data-action="clear-position" data-index="${index}">Use pointer</button>` : ''}</div></div>
  ${position ? `<div class="coordinate-grid"><label>X coordinate<input type="number" step="1" min="-2147483648" max="2147483647" data-index="${index}" data-field="x" value="${escape(position.x)}" required></label><label>Y coordinate<input type="number" step="1" min="-2147483648" max="2147483647" data-index="${index}" data-field="y" value="${escape(position.y)}" required></label></div>` : ''}`;
}
function render() {
  // Status and update events can arrive while a field is being edited. Replacing
  // the DOM must not discard the user's unfinished value or keyboard focus.
  const active = document.activeElement instanceof HTMLElement && app.contains(document.activeElement) ? document.activeElement : null;
  let selector = '';
  if (active?.id) selector = `#${CSS.escape(active.id)}`;
  else if (active?.dataset.field && active.dataset.index !== undefined) selector = `[data-field="${CSS.escape(active.dataset.field)}"][data-index="${CSS.escape(active.dataset.index)}"]`;
  else if (active?.dataset.action) selector = `[data-action="${CSS.escape(active.dataset.action)}"]${active.dataset.index !== undefined ? `[data-index="${CSS.escape(active.dataset.index)}"]` : ''}${active.dataset.mode ? `[data-mode="${CSS.escape(active.dataset.mode)}"]` : ''}`;
  else if (active instanceof HTMLInputElement && active.name) selector = `input[name="${CSS.escape(active.name)}"][value="${CSS.escape(active.value)}"]`;
  const editingValue = active instanceof HTMLInputElement && active.type === 'number' ? active.value : null;
  const sequence = settings.mode === 'sequence';
  const shortcuts = Array.isArray(status.available_shortcuts) ? status.available_shortcuts.filter((value): value is string => typeof value === 'string' && value.length > 0) : [];
  app.innerHTML = `<main class="shell">
    <header class="topbar"><div class="brand"><span class="brand-icon" aria-hidden="true">✳</span><div><strong>Auto Clicker</strong><span class="brand-sub">A little automation, in your control.</span></div></div><div class="top-actions"><label class="language-label"><span class="sr-only">Language</span><select id="language" aria-label="Language"><option value="en"${language === 'en' ? ' selected' : ''}>English</option><option value="ko"${language === 'ko' ? ' selected' : ''}>한국어</option><option value="ja"${language === 'ja' ? ' selected' : ''}>日本語</option></select></label><span class="open-source">OPEN SOURCE</span></div></header>
    <section class="intro"><div><p class="eyebrow">DESKTOP AUTOMATION</p><h1>Make every click count.</h1><p>Set up a click or build a sequence. Start when you're ready.</p></div><div class="status ${status.running ? 'active' : ''}" role="status"><span class="status-dot"></span>${status.running ? 'Running' : 'Ready'}</div></section>
    ${status.shortcut_error ? `<div class="alert" role="alert"><strong>Emergency stop shortcut unavailable. Starting is disabled.</strong><p class="hint">${escape(status.shortcut_error)}</p></div>` : ''}
    ${status.shortcut_warning ? `<div class="alert" role="alert"><strong>Some emergency shortcuts are unavailable. Use an available shortcut shown below.</strong><p class="hint">${escape(status.shortcut_warning)}</p></div>` : ''}
    ${notice || status.error ? `<div class="alert" role="alert">${escape(notice || status.error)}</div>` : ''}
    <div class="layout"><section class="workspace" aria-label="Click configuration">
      <div class="tabs" role="group" aria-label="Click mode"><button type="button" aria-pressed="${!sequence}" data-action="mode" data-mode="simple"${disabled(status.running || capturing || fileBusy)}>Simple click</button><button type="button" aria-pressed="${sequence}" data-action="mode" data-mode="sequence"${disabled(status.running || capturing || fileBusy)}>Sequence</button></div>
      <form id="config-form"><fieldset${disabled(status.running || capturing || fileBusy)}><legend class="sr-only">Click configuration</legend>
      ${sequence ? `<div class="section-heading"><div><p class="eyebrow">YOUR SEQUENCE</p><h2>Steps</h2><p>Actions run from top to bottom, then repeat.</p></div><span class="count">${settings.steps.length} ${settings.steps.length === 1 ? 'STEP' : 'STEPS'}</span></div>
      <div class="steps">${settings.steps.map((step, i) => `<article class="step"><div class="step-header"><div class="step-title"><span class="step-number">${String(i + 1).padStart(2, '0')}</span><strong>${step.kind === 'click' ? 'Click' : 'Wait'}</strong></div><div class="step-actions"><button type="button" aria-label="Move step ${i+1} up" data-action="up" data-index="${i}"${disabled(i === 0)}>↑</button><button type="button" aria-label="Move step ${i+1} down" data-action="down" data-index="${i}"${disabled(i === settings.steps.length - 1)}>↓</button><button type="button" aria-label="Duplicate step ${i+1}" data-action="duplicate" data-index="${i}"${disabled(settings.steps.length >= 1000)}>⧉</button><button type="button" aria-label="Remove step ${i+1}" data-action="remove" data-index="${i}">×</button></div></div>${step.kind === 'click' ? clickFields(step, String(i)) : `<label class="wait-field">Wait duration <span class="unit">ms</span><input type="number" min="1" max="86400000" step="1" data-index="${i}" data-field="duration_ms" value="${escape(step.duration_ms)}" required></label>`}</article>`).join('') || '<div class="empty">Your sequence is empty. Add a click or a wait to get started.</div>'}</div>
      <div class="add-actions"><button type="button" class="button secondary" data-action="add-click"${disabled(settings.steps.length >= 1000)}>+ Add click</button><button type="button" class="button secondary" data-action="add-wait"${disabled(settings.steps.length >= 1000)}>+ Add wait</button></div>` : `<div class="section-heading"><div><p class="eyebrow">SINGLE ACTION</p><h2>Click settings</h2><p>Choose how and where to click.</p></div></div><div class="simple-fields">${clickFields(settings.simple, 'simple')}</div>`}
      <div class="repeat-section"><div><span class="label">Repeat</span><p class="hint">Choose when the run should stop.</p></div><div class="repeat-controls"><label class="radio"><input type="radio" name="repeatMode" value="forever"${checked(settings.repeat === null)}> Until stopped</label><label class="radio"><input type="radio" name="repeatMode" value="count"${checked(settings.repeat !== null)}> <input aria-label="Number of repetitions" id="repeat-count" type="number" min="1" max="1000000" step="1" required value="${escape(settings.repeat ?? 1)}"${disabled(settings.repeat === null)}> times</label></div></div>
      <div class="start-delay"><label for="start-delay">Start delay <span class="unit">seconds</span></label><input id="start-delay" type="number" min="0" max="60" step="1" required value="${escape(settings.startDelayMs / 1000)}"><p class="hint">Wait before the first click so you can switch windows. You can stop during the wait.</p></div>
      <div class="backup-section"><span class="label">Settings backup</span><p class="hint">Export your settings or replace them with a saved backup.</p><div class="add-actions"><button type="button" class="button secondary" data-action="export-settings">Export settings</button><button type="button" class="button secondary" data-action="import-settings">Import settings</button></div></div>
      </fieldset></form></section>
      <aside class="control-panel"><div><p class="eyebrow">RUN CONTROL</p><h2>${status.running ? 'In progress' : 'Ready when you are'}</h2><p>${status.running ? `Completed cycles: ${status.completed_cycles}` : 'Review your settings, then start clicking.'}</p></div>
      <button type="button" class="button primary ${status.running ? 'stop' : ''}" data-action="toggle"${disabled(toggleDisabled(status, statusReady, capturing || fileBusy, updateState === 'installing'))}>${status.running ? '<span aria-hidden="true">■</span> Stop clicking' : '<span aria-hidden="true">▶</span> Start clicking'}</button>
      <div class="shortcut"><span>Global emergency stop</span>${shortcuts.length ? shortcuts.map(shortcut => `<kbd>${escape(shortcut)}</kbd>`).join('<span>or</span>') : `<span>${statusReady ? 'No shortcut available' : 'Checking shortcuts…'}</span>`}</div>${isMac && shortcuts.includes('Ctrl+Shift+F8') ? '<p class="hint">On some Mac keyboards, hold Fn or Globe with F8 to use it as a function key.</p>' : ''}${shortcuts.length ? '<p class="safety">You can stop a run at any time with the shortcut. Check system permissions if clicking is unavailable.</p>' : ''}
      <div class="updates"><span class="label">App updates</span>
      <p class="hint">${updateState === 'checking' ? 'Checking for updates…' : updateState === 'installing' ? 'Installing update…' : updateState === 'current' ? 'You have the latest version.' : updateState === 'installed' ? 'Update installed. Restart the app to use it.' : updateState === 'available' && updateInfo ? `Version ${escape(updateInfo.version)} is available.` : updateState === 'error' ? escape(updateError) : 'Updates are checked on startup. Installation requires your choice.'}</p>
      ${updateState === 'available' && updateInfo?.notes ? `<p class="update-notes">${escape(updateInfo.notes)}</p>` : ''}
      ${updateState === 'available' ? `<button type="button" class="button secondary update-button" data-action="install-update"${disabled(status.running || fileBusy)}>Install update</button>` : `<button type="button" class="button secondary update-button" data-action="check-update"${disabled(fileBusy || updateState === 'checking' || updateState === 'installing' || updateState === 'installed')}>Check for updates</button>`}</div></aside></div>
    <footer><span>Built for the way you work.</span><span>Settings stay on this device.</span></footer></main>`;
  document.documentElement.lang = language;
  translateDom(app, language);
  if (selector) {
    const replacement = app.querySelector<HTMLElement>(selector);
    if (replacement && !(replacement instanceof HTMLButtonElement && replacement.disabled) && !(replacement instanceof HTMLInputElement && replacement.disabled)) {
      if (editingValue !== null && replacement instanceof HTMLInputElement) replacement.value = editingValue;
      replacement.focus({ preventScroll: true });
    }
  }
}
function stepAt(index: string): Step { return index === 'simple' ? settings.simple : settings.steps[Number(index)]; }
function cloneStep(step: Step): Step {
  return step.kind === 'click'
    ? { ...step, position: step.position ? { ...step.position } : null }
    : { ...step };
}
async function readBackup(path: string): Promise<string> {
  const file = await openFile(path, { read: true });
  try {
    // Read at most one byte beyond the limit, even if the file grows while reading.
    const bytes = new Uint8Array(MAX_BACKUP_BYTES + 1);
    let offset = 0;
    while (offset < bytes.length) {
      const count = await file.read(bytes.subarray(offset));
      if (count === null) break;
      if (count <= 0) throw new Error('Unable to read backup');
      offset += count;
    }
    if (offset > MAX_BACKUP_BYTES) throw new Error('Backup too large');
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, offset));
  } finally { await file.close(); }
}
function changeInput(target: HTMLInputElement | HTMLSelectElement) {
  if (target instanceof HTMLInputElement && target.type === 'number' && (!target.value || !target.validity.valid)) return;
  if (target.name === 'repeatMode') { settings.repeat = target.value === 'forever' ? null : 1; save(); render(); return; }
  if (target.id === 'repeat-count') { settings.repeat = Number(target.value); save(); return; }
  if (target.id === 'start-delay') { settings.startDelayMs = Number(target.value) * 1000; save(); return; }
  const index = target.dataset.index, field = target.dataset.field;
  if (index === undefined || !field) return;
  const step = stepAt(index);
  if (!step) return;
  if (step.kind === 'click') {
    if (field === 'button') step.button = target.value as Click['button'];
    else if (field === 'clicks') step.clicks = Number(target.value) as 1 | 2;
    else if (field === 'interval_ms') step.interval_ms = Number(target.value);
    else if ((field === 'x' || field === 'y') && step.position) step.position[field] = Number(target.value);
  } else if (field === 'duration_ms') step.duration_ms = Number(target.value);
  save();
}
app.addEventListener('input', e => { const t = e.target; if (t instanceof HTMLInputElement && t.type === 'number') changeInput(t); });
app.addEventListener('change', e => { const t = e.target; if (t instanceof HTMLSelectElement && t.id === 'language') { if (t.value === 'en' || t.value === 'ko' || t.value === 'ja') { language = t.value; try { localStorage.setItem('open-clicker-language', language); } catch { /* selection lasts for this session */ } render(); } return; } if (t instanceof HTMLSelectElement || (t instanceof HTMLInputElement && t.type === 'radio')) changeInput(t); });
app.addEventListener('click', async e => {
  const button = (e.target as HTMLElement).closest<HTMLButtonElement>('button[data-action]');
  if (!button || fileBusy) return;
  const { action, index = '' } = button.dataset;
  if (action === 'export-settings' || action === 'import-settings') {
    if (status.running || capturing || updateState === 'installing') return;
    fileBusy = true; notice = ''; render();
    try {
      const filters = [{ name: 'JSON', extensions: ['json'] }];
      if (action === 'export-settings') {
        const path = await saveDialog({ title: translate('Export settings', language), defaultPath: 'auto-clicker-settings.json', filters });
        if (path) { await writeTextFile(path, serializeBackup(settings)); notice = 'Settings exported.'; }
      } else {
        const path = await openDialog({ title: translate('Import settings', language), multiple: false, directory: false, filters });
        if (path) {
          const imported = parseBackup(await readBackup(path));
          // Persist first so an unavailable store cannot silently replace a usable configuration.
          localStorage.setItem(key, JSON.stringify(imported));
          settings = imported; notice = 'Settings imported.';
        }
      }
    } catch {
      notice = action === 'export-settings' ? 'Could not export settings. Please try again.' : 'Could not import settings. Check the file and try again.';
    } finally { fileBusy = false; render(); }
    return;
  }
  if (action === 'check-update') {
    updateState = 'checking'; render();
    try { updateInfo = await invoke<UpdateInfo | null>('check_update'); updateState = updateInfo ? 'available' : 'current'; }
    catch (error) { updateState = 'error'; updateError = String(error); }
    render(); return;
  }
  if (action === 'install-update') {
    if (!updateInfo || status.running) return;
    updateState = 'installing'; render();
    try { await invoke('install_update', { expectedVersion: updateInfo.version }); updateState = 'installed'; }
    catch (error) { updateState = 'error'; updateError = String(error); }
    render(); return;
  }
  if (action === 'toggle') {
    if (toggleDisabled(status, statusReady, capturing || fileBusy, updateState === 'installing')) return;
    notice = '';
    if (status.running) { try { await invoke('stop_run'); } catch (error) { notice = String(error); render(); } return; }
    const form = document.querySelector<HTMLFormElement>('#config-form')!;
    if (!form.reportValidity()) return;
    const steps = settings.mode === 'simple' ? [settings.simple] : settings.steps;
    if (!steps.length) { notice = 'Add at least one step before starting.'; render(); return; }
    try { await invoke('start_run', { config: { steps, repeat: settings.repeat, start_delay_ms: settings.startDelayMs } }); } catch (error) { notice = String(error); render(); }
    return;
  }
  if (status.running || capturing) return;
  if (action === 'mode') settings.mode = button.dataset.mode === 'sequence' ? 'sequence' : 'simple';
  if (action === 'add-click' && settings.steps.length < 1000) settings.steps.push(defaultClick());
  if (action === 'add-wait' && settings.steps.length < 1000) settings.steps.push({ kind: 'wait', duration_ms: 1000 });
  const i = Number(index);
  if (action === 'duplicate' && settings.steps.length < 1000 && settings.steps[i]) settings.steps.splice(i + 1, 0, cloneStep(settings.steps[i]));
  if (action === 'remove') settings.steps.splice(i, 1);
  if ((action === 'up' && i > 0) || (action === 'down' && i < settings.steps.length - 1)) { const j = i + (action === 'up' ? -1 : 1); [settings.steps[i], settings.steps[j]] = [settings.steps[j], settings.steps[i]]; }
  if (action === 'clear-position') { const step = stepAt(index); if (step?.kind === 'click') step.position = null; }
  if (action === 'capture') {
    capturing = true;
    for (let seconds = 3; seconds > 0; seconds--) { notice = `Move your pointer to the target position. Capturing in ${seconds}…`; render(); await new Promise(resolve => setTimeout(resolve, 1000)); }
    try { const position = await invoke<Position>('cursor_position'); const step = stepAt(index); if (step?.kind === 'click') step.position = position; notice = `Position captured: ${position.x}, ${position.y}.`; }
    catch (error) { notice = `Could not capture the pointer position: ${String(error)}`; }
    capturing = false;
  }
  save(); render();
});
render();
// Startup checks are silent on failure (for example, before the first release exists).
updateState = 'checking';
render();
void invoke<UpdateInfo | null>('check_update').then(info => {
  updateInfo = info; updateState = info ? 'available' : 'current'; render();
}).catch(() => { updateState = 'idle'; render(); /* manual checks report the error */ });
const statusSnapshotGate = new StatusSnapshotGate();
void listen<Status>('run-status', event => {
  statusSnapshotGate.eventReceived();
  status = event.payload; statusReady = true; render();
}).then(async () => {
  const checkpoint = statusSnapshotGate.checkpoint();
  const value = await invoke<Status>('get_status');
  if (statusSnapshotGate.canApply(checkpoint)) { status = value; statusReady = true; render(); }
}).catch(error => { notice = `Desktop connection unavailable: ${String(error)}`; render(); });
