export type Status = { running: boolean; completed_cycles: number; error: string | null; shortcut_error: string | null };

// A working emergency stop must be confirmed before a run starts. Once a run
// exists, its stop control remains available regardless of other UI activity.
export function toggleDisabled(status: Status, ready: boolean, capturing: boolean, installing: boolean): boolean {
  return status.running ? false : !ready || capturing || installing || Boolean(status.shortcut_error);
}
