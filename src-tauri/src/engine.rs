use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize)]
pub struct Config {
    pub steps: Vec<Step>,
    pub repeat: Option<u64>,
}
#[derive(Clone, Debug, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Step {
    Click {
        button: MouseButton,
        clicks: u8,
        position: Option<Position>,
        interval_ms: u64,
    },
    Wait {
        duration_ms: u64,
    },
}
#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MouseButton {
    Left,
    Right,
    Middle,
}
#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
pub struct Position {
    pub x: i32,
    pub y: i32,
}

pub fn validate(config: &Config) -> Result<(), String> {
    if config.steps.is_empty() {
        return Err("Add at least one step.".into());
    }
    if config.steps.len() > 1000 {
        return Err("Too many steps (maximum 1000).".into());
    }
    if config.repeat == Some(0) {
        return Err("Repeat count must be at least one.".into());
    }
    for step in &config.steps {
        match step {
            Step::Click {
                clicks,
                interval_ms,
                ..
            } if !matches!(clicks, 1 | 2) || *interval_ms < 10 || *interval_ms > 86_400_000 => {
                return Err(
                    "Click count must be 1 or 2 and interval must be between 10 ms and 24 hours."
                        .into(),
                )
            }
            Step::Wait { duration_ms } if *duration_ms == 0 || *duration_ms > 86_400_000 => {
                return Err("Wait must be between 1 ms and 24 hours.".into())
            }
            _ => {}
        }
    }
    Ok(())
}
#[cfg(test)]
#[path = "engine_tests.rs"]
mod tests;
