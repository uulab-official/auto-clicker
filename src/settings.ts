export type Position = { x: number; y: number };
export type Click = { kind: 'click'; button: 'left' | 'right' | 'middle'; clicks: 1 | 2; position: Position | null; interval_ms: number };
export type Wait = { kind: 'wait'; duration_ms: number };
export type Step = Click | Wait;
export type Settings = { mode: 'simple' | 'sequence'; simple: Click; steps: Step[]; repeat: number | null; startDelayMs: number };
export const defaultClick = (): Click => ({ kind: 'click', button: 'left', clicks: 1, position: null, interval_ms: 1000 });
export const defaults = (): Settings => ({ mode: 'simple', simple: defaultClick(), steps: [defaultClick()], repeat: null, startDelayMs: 3000 });
const isInteger = (value: unknown, min: number, max: number): value is number => Number.isInteger(value) && (value as number) >= min && (value as number) <= max;
function isClick(value: unknown): value is Click {
  if (!value || typeof value !== 'object') return false;
  const c = value as Record<string, unknown>;
  if (c.kind !== 'click' || !['left', 'right', 'middle'].includes(String(c.button)) || (c.clicks !== 1 && c.clicks !== 2) || !isInteger(c.interval_ms, 10, 86400000)) return false;
  if (c.position === null) return true;
  if (!c.position || typeof c.position !== 'object') return false;
  const p = c.position as Record<string, unknown>;
  return isInteger(p.x, -2147483648, 2147483647) && isInteger(p.y, -2147483648, 2147483647);
}
function isStep(value: unknown): value is Step {
  if (isClick(value)) return true;
  if (!value || typeof value !== 'object') return false;
  const w = value as Record<string, unknown>;
  return w.kind === 'wait' && isInteger(w.duration_ms, 1, 86400000);
}
export function validateSettings(value: unknown): Settings | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const s = value as Record<string, unknown>;
  if ((s.mode !== 'simple' && s.mode !== 'sequence') || !isClick(s.simple) || !Array.isArray(s.steps) || s.steps.length > 1000 || !s.steps.every(isStep) || !(s.repeat === null || isInteger(s.repeat, 1, 1000000))) return null;
  if (s.startDelayMs !== undefined && (!isInteger(s.startDelayMs, 0, 60000) || s.startDelayMs % 1000 !== 0)) return null;
  return { mode: s.mode, simple: s.simple, steps: s.steps, repeat: s.repeat as number | null, startDelayMs: (s.startDelayMs ?? 0) as number };
}
export function parseSettings(raw: string | null): Settings {
  try { return raw ? validateSettings(JSON.parse(raw)) ?? defaults() : defaults(); } catch { return defaults(); }
}

export const MAX_BACKUP_BYTES = 1024 * 1024;
export function serializeBackup(settings: Settings): string {
  const valid = validateSettings(settings);
  if (!valid) throw new Error('Invalid settings');
  return JSON.stringify({ format: 'auto-clicker-settings', version: 1, settings: valid }, null, 2) + '\n';
}
export function parseBackup(raw: string): Settings {
  if (new TextEncoder().encode(raw).byteLength > MAX_BACKUP_BYTES) throw new Error('Backup too large');
  const value: unknown = JSON.parse(raw);
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid backup');
  const object = value as Record<string, unknown>;
  const settings = object.format === undefined ? object : object.format === 'auto-clicker-settings' && object.version === 1 ? object.settings : null;
  const valid = validateSettings(settings);
  if (!valid) throw new Error('Invalid backup');
  return valid;
}
