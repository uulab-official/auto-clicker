// Built against the exact global-hotkey crate used by the app under test.
fn main() {
    let name = std::env::args().nth(1).expect("shortcut required");
    assert!(matches!(name.as_str(), "Control+Shift+F8" | "Control+Shift+Escape"));
    let shortcut: global_hotkey::hotkey::HotKey = name.parse().unwrap();
    println!("{}", shortcut.id());
}
