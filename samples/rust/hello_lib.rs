// Simple Library to generate a proto message
// Copyright (c) 2024 Radiant Science Inc.

use samples::proto::SampleMessage;

pub fn get_proto() -> SampleMessage {
    SampleMessage {
        name: "Rust".to_string(),
        tags: vec!["rust".to_string(), "proto".to_string()],
    }
}
