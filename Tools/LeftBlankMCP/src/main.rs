#[cfg(not(target_os = "macos"))]
compile_error!("LeftBlankMCP supports macOS only.");

mod bridge;
mod discovery;
mod exports;
mod server;
mod tools;

use bridge::{Failure, MAX_MESSAGE_BYTES};
use discovery::Configuration;
use futures_util::{StreamExt, future::ready};
use rmcp::{
    RoleServer, ServiceExt,
    service::{RxJsonRpcMessage, TxJsonRpcMessage},
    transport::async_rw::JsonRpcMessageCodec,
};
use serde_json::json;
use std::{path::PathBuf, process::ExitCode};
use tokio_util::codec::{FramedRead, FramedWrite};

#[tokio::main]
async fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_max_level(tracing_subscriber::filter::LevelFilter::WARN)
        .with_writer(std::io::stderr)
        .without_time()
        .with_ansi(false)
        .init();
    match run().await {
        Ok(code) => code,
        Err(error) => {
            eprintln!("LeftBlankMCP: {error}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<ExitCode, Failure> {
    let mut app_bundle = None;
    let mut mode = "stdio";
    let mut args = std::env::args_os().skip(1);
    while let Some(argument) = args.next() {
        match argument.to_str() {
            Some("--app-bundle") => {
                if app_bundle.is_some() {
                    return Err(Failure::new(
                        "invalid_arguments",
                        "Provide --app-bundle only once.",
                    ));
                }
                app_bundle = Some(PathBuf::from(args.next().ok_or_else(|| {
                    Failure::new(
                        "invalid_arguments",
                        "--app-bundle needs an absolute app path.",
                    )
                })?));
            }
            Some("--describe" | "--check") if mode == "stdio" => {
                mode = if argument == "--check" {
                    "check"
                } else {
                    "describe"
                }
            }
            Some("--help" | "-h") => {
                println!(
                    "LeftBlankMCP [--app-bundle /Applications/LeftBlank.app] [--describe | --check]\nDefault: MCP over stdio. --describe prints installation metadata. --check probes Agent Access and exits nonzero when unavailable."
                );
                return Ok(ExitCode::SUCCESS);
            }
            _ => {
                return Err(Failure::new(
                    "invalid_arguments",
                    "Unknown option. Use --help for usage.",
                ));
            }
        }
    }
    let config = match Configuration::discover(app_bundle) {
        Ok(config) => config,
        Err(error) if mode != "stdio" => {
            println!("{}", json!({"connected":false,"error":error}));
            return Ok(ExitCode::FAILURE);
        }
        Err(error) => return Err(error),
    };
    if mode == "describe" {
        println!("{}", json!(config.descriptor));
        return Ok(ExitCode::SUCCESS);
    }
    if mode == "check" {
        let result = config.bridge.send("get_status", json!({})).await;
        let connected = result.is_ok();
        match result {
            Ok(status) => println!(
                "{}",
                json!({"connected":true,"server":config.descriptor,"status":status})
            ),
            Err(error) => println!(
                "{}",
                json!({"connected":false,"server":config.descriptor,"error":error})
            ),
        }
        return Ok(if connected {
            ExitCode::SUCCESS
        } else {
            ExitCode::FAILURE
        });
    }
    let server = server::LeftBlankServer::new(
        config.bridge,
        config.descriptor.version,
        config.descriptor.name,
    );
    // The SDK's default async reader has no line cap. Its public codec lets
    // stdio use the same bounded framing as the private app bridge.
    let stream = FramedRead::new(
        tokio::io::stdin(),
        JsonRpcMessageCodec::<RxJsonRpcMessage<RoleServer>>::new_with_max_length(MAX_MESSAGE_BYTES),
    )
    .take_while(|result| {
        if result.is_err() {
            eprintln!("LeftBlankMCP: invalid or oversized stdio message; closing connection.");
        }
        ready(result.is_ok())
    })
    .map(|result| result.expect("take_while rejected errors"));
    let sink = FramedWrite::new(
        tokio::io::stdout(),
        JsonRpcMessageCodec::<TxJsonRpcMessage<RoleServer>>::new_with_max_length(MAX_MESSAGE_BYTES),
    );
    let service = server.serve((sink, stream)).await.map_err(|_| {
        Failure::new(
            "stdio_failed",
            "Cannot initialize the MCP stdio connection.",
        )
    })?;
    service
        .waiting()
        .await
        .map_err(|_| Failure::new("stdio_failed", "The MCP stdio connection failed."))?;
    Ok(ExitCode::SUCCESS)
}
