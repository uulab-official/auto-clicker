//! Restricted Wayland portal experiment. Not wired into the shipping app.
//!
//! This model deliberately has no coordinates. It exists to test the safety
//! preconditions before any input is allowed, not to advertise Wayland support.

#[derive(Debug, Clone, Copy, Default)]
pub struct SafetyGate {
    shortcut_bound: bool,
    pointer_granted: bool,
    app_hidden: bool,
    stopped: bool,
}

impl SafetyGate {
    pub fn set_shortcut_bound(&mut self, value: bool) {
        self.shortcut_bound = value;
    }
    pub fn set_pointer_granted(&mut self, value: bool) {
        self.pointer_granted = value;
    }
    pub fn set_app_hidden(&mut self, value: bool) {
        self.app_hidden = value;
    }
    pub fn stop(&mut self) {
        self.stopped = true;
    }
    pub fn can_click(&self) -> bool {
        self.shortcut_bound && self.pointer_granted && self.app_hidden && !self.stopped
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_permission_is_required_and_loss_stops_input() {
        let mut gate = SafetyGate::default();
        assert!(!gate.can_click());
        gate.set_shortcut_bound(true);
        assert!(!gate.can_click());
        gate.set_pointer_granted(true);
        assert!(!gate.can_click());
        gate.set_app_hidden(true);
        assert!(gate.can_click());
        gate.set_pointer_granted(false);
        assert!(!gate.can_click());
        gate.set_pointer_granted(true);
        gate.set_shortcut_bound(false);
        assert!(!gate.can_click());
        gate.set_shortcut_bound(true);
        gate.set_app_hidden(false);
        assert!(!gate.can_click());
        gate.set_app_hidden(true);
        gate.stop();
        assert!(!gate.can_click());
        gate.set_shortcut_bound(true);
        assert!(!gate.can_click());
    }
}
