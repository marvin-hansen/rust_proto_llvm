// Simple Library to generate a proto message
// Copyright (c) 2024 Radiant Science Inc.

use proto_bindings::proto::{SampleMessage, SubMessage};
use std::time::{Duration, SystemTime};

pub fn get_proto() -> SampleMessage {
    SampleMessage {
        name: "Rust".to_string(),
        time: None,
        duration: None,
        tags: vec!["rust".to_string(), "proto".to_string()],
        subs : vec![SubMessage{flag: true, value: 3.4f32}],
        meta: Some(SubMessage{flag: false, value: 0.0f32}),
    }
}
