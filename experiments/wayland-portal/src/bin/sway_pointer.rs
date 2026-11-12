//! A test-only wlroots virtual pointer, used by the mock portal inside Sway.
//! It cannot run outside the isolated GitHub runner session.
#[cfg(target_os = "linux")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use enigo::{Button, Coordinate, Direction, Enigo, Mouse, Settings};
    use std::{
        env,
        io::{self, BufRead, Write},
        os::unix::fs::FileTypeExt,
        path::Path,
    };
    let runtime = env::var("XDG_RUNTIME_DIR")?;
    let temp = env::var("RUNNER_TEMP")?;
    if env::var("CI").as_deref() != Ok("true")
        || env::var("GITHUB_ACTIONS").as_deref() != Ok("true")
        || env::var("WAYLAND_DISPLAY").as_deref() != Ok("wayland-ci")
        || !Path::new(&runtime).starts_with(Path::new(&temp))
        || !std::fs::metadata(Path::new(&runtime).join("wayland-ci"))?
            .file_type()
            .is_socket()
        || env::var("DISPLAY").is_ok()
    {
        return Err("Virtual pointer test requires the isolated CI compositor".into());
    }
    let mut pointer = Enigo::new(&Settings::default())?;
    pointer.move_mouse(400, 300, Coordinate::Abs)?;
    println!("POINTER_READY");
    io::stdout().flush()?;
    for command in io::stdin().lock().lines() {
        match command?.as_str() {
            "press" => pointer.button(Button::Left, Direction::Press)?,
            "release" => pointer.button(Button::Left, Direction::Release)?,
            _ => return Err("Unknown pointer command".into()),
        }
        println!("OK");
        io::stdout().flush()?;
    }
    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("The isolated Sway pointer is only available on Linux");
}
