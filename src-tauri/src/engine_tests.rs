use super::*;

#[test]
fn rejects_start_delays_over_one_minute() {
    let config: Config = serde_json::from_str(
        r#"{"steps":[{"kind":"wait","duration_ms":1}],"repeat":1,"start_delay_ms":60001}"#,
    )
    .unwrap();
    assert!(validate(&config).is_err());
}

#[test]
fn rejects_empty_or_busy_loop_configurations() {
    assert!(validate(&Config {
        steps: vec![],
        repeat: None,
        start_delay_ms: 0
    })
    .is_err());
    assert!(validate(&Config {
        steps: vec![Step::Wait { duration_ms: 0 }],
        repeat: None,
        start_delay_ms: 0
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
        repeat: Some(2),
        start_delay_ms: 0
    })
    .is_ok());
    assert!(validate(&Config {
        steps: vec![step],
        repeat: Some(0),
        start_delay_ms: 0
    })
    .is_err());
}
