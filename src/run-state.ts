export type Status = { running: boolean; completed_cycles: number; error: string | null; shortcut_error: string | null; shortcut_warning?: string | null; available_shortcuts?: string[] };

// A working emergency stop must be confirmed before a run starts. Once a run
// exists, its stop control remains available regardless of other UI activity.
export function toggleDisabled(status: Status, ready: boolean, capturing: boolean, installing: boolean): boolean {
  return status.running ? false : !ready || capturing || installing || Boolean(status.shortcut_error) || !Array.isArray(status.available_shortcuts) || !status.available_shortcuts.some(shortcut => typeof shortcut === 'string' && shortcut.length > 0);
}

// A snapshot requested after subscribing can arrive after a newer event.
export class StatusSnapshotGate {
  private generation = 0;
  eventReceived(): void { this.generation += 1; }
  checkpoint(): number { return this.generation; }
  canApply(checkpoint: number): boolean { return checkpoint === this.generation; }
}
