// Built against the exact global-hotkey crate used by the app under test.
fn main() {
    let shortcut: global_hotkey::hotkey::HotKey = "Control+Shift+F8".parse().unwrap();
    println!("{}", shortcut.id());
}
