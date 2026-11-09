use super::*;

#[test]
fn rejects_empty_or_busy_loop_configurations() {
    assert!(validate(&Config {
        steps: vec![],
        repeat: None
    })
    .is_err());
    assert!(validate(&Config {
        steps: vec![Step::Wait { duration_ms: 0 }],
        repeat: None
    })
    .is_err());
}

#[test]
fn accepts_a_valid_click_sequence_and_rejects_zero_repeats() {
    let step = Step::Click {
        button: MouseButton::Left,
        clicks: 1,
        position: None,
        interval_ms: 50,
    };
    assert!(validate(&Config {
        steps: vec![step.clone()],
        repeat: Some(2)
    })
    .is_ok());
    assert!(validate(&Config {
        steps: vec![step],
        repeat: Some(0)
    })
    .is_err());
}
