# Production readiness — 2026-11-10

The published release is v0.1.1. The v0.1.2 draft and tag were created before
the subsequent safety and UI changes on `main`; do not publish that draft as if
it included those changes. Prepare a new version/tag and verify its own assets
before publishing.

Changes on `main` add safety checks for unreachable click positions, unavailable
emergency shortcuts, Wayland sessions and stale update confirmations. A Wayland
session cannot start clicking because the X11 global shortcut does not guarantee
emergency stop. Update checks contact GitHub, while clicking and settings remain
local. A running click sequence must always be stoppable from the app.

Evidence and limitations:

- Local Rust, frontend and release metadata tests cover state transitions,
  corrupted settings, cancellation and updater metadata; these do not establish
  native input behavior by themselves.
- Disposable GitHub runners verified a Linux X11 target received clicks and the
  emergency shortcut stopped further clicks ([run](https://github.com/uulab-official/auto-clicker/actions/runs/42726022014)).
  This does not establish Wayland or real multi-monitor behavior.
- The changed app passed a macOS isolated install and update test ([run](https://github.com/uulab-official/auto-clicker/actions/runs/42725503599))
  and Linux isolated install and update test ([run](https://github.com/uulab-official/auto-clicker/actions/runs/42725503250)).
- Windows installers are not Authenticode-signed and can be warned or blocked by
  SmartScreen or organizational policies. No warning-free installation claim is
  made.
- `cargo audit` reported the upstream Linux GTK dependency warnings
  RUSTSEC-2024-0370 (unmaintained proc-macro-error) and RUSTSEC-2024-0429
  (glib VariantStrIter unsoundness). These are transitive framework dependencies;
  they are not claims that this application invokes the affected iterator.
- Actual mouse injection, emergency shortcut, display scaling, negative/off-screen
  coordinates, accessibility permissions, window focus and screen readers still
  need acceptance on real Mac, Windows and Linux systems. Do not drive the user's
  physical input while performing automated checks.

A successful build, a mocked browser test or a virtual desktop run is not a
substitute for platform acceptance or a signed Windows publisher identity.
