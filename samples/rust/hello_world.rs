// Simple Test for Rust.
// Copyright (c) 2024 Radiant Science Inc.

// import hello_lib
use samples::rust::hello_lib::get_proto;

fn main() -> anyhow::Result<()> {
    // create proto msg
    let proto = get_proto();
    // print the message
    println!("{:?}", proto);
    println!("Hello, world!");
    Ok(())
}
