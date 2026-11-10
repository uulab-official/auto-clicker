export type Position = { x: number; y: number };
export type Click = { kind: 'click'; button: 'left' | 'right' | 'middle'; clicks: 1 | 2; position: Position | null; interval_ms: number };
export type Wait = { kind: 'wait'; duration_ms: number };
export type Step = Click | Wait;
export type Settings = { mode: 'simple' | 'sequence'; simple: Click; steps: Step[]; repeat: number | null };
export const defaultClick = (): Click => ({ kind: 'click', button: 'left', clicks: 1, position: null, interval_ms: 1000 });
export const defaults = (): Settings => ({ mode: 'simple', simple: defaultClick(), steps: [defaultClick()], repeat: null });
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
export function parseSettings(raw: string | null): Settings {
  try {
    if (!raw) return defaults();
    const value: unknown = JSON.parse(raw);
    if (!value || typeof value !== 'object') return defaults();
    const s = value as Record<string, unknown>;
    if ((s.mode !== 'simple' && s.mode !== 'sequence') || !isClick(s.simple) || !Array.isArray(s.steps) || s.steps.length > 1000 || !s.steps.every(isStep) || !(s.repeat === null || isInteger(s.repeat, 1, 1000000))) return defaults();
    return s as Settings;
  } catch { return defaults(); }
}
