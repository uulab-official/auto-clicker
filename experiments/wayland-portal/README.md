# Wayland portal experiment — not a supported backend

This is an isolated CI experiment, not part of the Auto Clicker application.
The app must continue to block clicking on Wayland. The experiment creates no
application window, has no coordinate capture or fixed-position clicks, and
never supports a continuous run. Production integration still requires hiding
and verifying the actual window, restoring it on every outcome, real compositor
portal tests and coordinate/source mapping.

The probe requests a user-bound emergency shortcut via the GlobalShortcuts
portal and pointer control via the RemoteDesktop portal. It checks the actual
bound trigger and the granted pointer capability and monitors both sessions for
closure or shortcut revocation. It will send at most one click, and only on an
explicit opt-in inside its isolated GitHub runner. The CI portal service is a
mock: it records D-Bus button requests and never touches the compositor or real
input. The accompanying Weston instance proves the test process is inside a
Wayland session; it does not make the mocked portal a real compositor test.

Open issues include stop-versus-button-call races, portal request timeouts,
dialog parenting and cancellation, application identity for desktop portal
registration, portal backend availability, mapping arbitrary display layouts,
accessibility and translations, and ensuring cleanup if the compositor or bus
disconnects. A passing mock test is not evidence of physical input delivery or
that every compositor implements these portals.
