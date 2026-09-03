use std::{
    fs,
    path::PathBuf,
    sync::mpsc::{self, Receiver},
};

use anyhow::{Context, Result};
use iroh::{endpoint::{presets, Connection}, Endpoint, EndpointId, SecretKey};
use serde::{Deserialize, Serialize};
use tokio::{sync::mpsc as tokio_mpsc, task::JoinHandle};

use crate::wire::{self, Kind};

#[derive(Debug)]
pub enum Command {
    Connect(String),
    Disconnect,
    BeginTransmit,
    Audio(Vec<u8>),
    EndTransmit,
    SetProfile { name: String, avatar_data: Option<String> },
    Shutdown,
}

#[derive(Debug)]
pub enum Event {
    EndpointReady(String),
    Connected,
    Disconnected,
    Peer { id: String, name: String, avatar_data: Option<String> },
    RemoteTransmit(bool),
    RemoteAudio(Vec<u8>),
    Error(String),
}

pub struct Handle {
    pub commands: tokio_mpsc::UnboundedSender<Command>,
    pub events: Receiver<Event>,
}

impl Handle {
    pub fn spawn(name: String, avatar_data: Option<String>) -> Self {
        let (command_tx, command_rx) = tokio_mpsc::unbounded_channel();
        let (event_tx, event_rx) = mpsc::channel();

        std::thread::Builder::new()
            .name("landline-iroh".into())
            .spawn(move || {
                let runtime = tokio::runtime::Builder::new_multi_thread()
                    .enable_all()
                    .thread_name("landline-iroh-worker")
                    .build();

                match runtime {
                    Ok(runtime) => {
                        if let Err(error) = runtime.block_on(run(command_rx, event_tx.clone(), name, avatar_data)) {
                            let _ = event_tx.send(Event::Error(error.to_string()));
                        }
                    }
                    Err(error) => {
                        let _ = event_tx.send(Event::Error(format!("Unable to start Iroh runtime: {error}")));
                    }
                }
            })
            .expect("failed to spawn Landline Iroh thread");

        Self {
            commands: command_tx,
            events: event_rx,
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HelloMessage {
    endpoint_id: String,
    name: String,
    avatar_kind: String,
    avatar_data: Option<String>,
}

struct Session {
    id: u64,
    frames: tokio_mpsc::UnboundedSender<Vec<u8>>,
    task: JoinHandle<()>,
}

enum Internal {
    Incoming(Connection),
    AcceptError(String),
    SessionEnded { id: u64, error: Option<String> },
}

async fn run(
    mut commands: tokio_mpsc::UnboundedReceiver<Command>,
    events: mpsc::Sender<Event>,
    mut local_name: String,
    mut local_avatar_data: Option<String>,
) -> Result<()> {
    let secret = load_or_create_secret()?;
    let endpoint = Endpoint::builder(presets::N0)
        .secret_key(secret)
        .alpns(vec![wire::ALPN.to_vec()])
        .bind()
        .await
        .context("unable to bind the Iroh endpoint")?;

    let endpoint_id = endpoint.id().to_string();
    let _ = events.send(Event::EndpointReady(endpoint_id.clone()));

    let (internal_tx, mut internal_rx) = tokio_mpsc::unbounded_channel();
    let accept_endpoint = endpoint.clone();
    let accept_tx = internal_tx.clone();
    let accept_task = tokio::spawn(async move {
        while let Some(incoming) = accept_endpoint.accept().await {
            let tx = accept_tx.clone();
            tokio::spawn(async move {
                match incoming.await {
                    Ok(connection) => {
                        let _ = tx.send(Internal::Incoming(connection));
                    }
                    Err(error) => {
                        let _ = tx.send(Internal::AcceptError(error.to_string()));
                    }
                }
            });
        }
    });

    let mut session: Option<Session> = None;
    let mut next_session_id = 1_u64;

    loop {
        tokio::select! {
            command = commands.recv() => {
                let Some(command) = command else { break; };
                match command {
                    Command::Connect(raw) => {
                        let raw = raw.trim();
                        if raw.is_empty() {
                            continue;
                        }

                        close_session(&mut session);
                        let peer: EndpointId = match raw.parse() {
                            Ok(peer) => peer,
                            Err(error) => {
                                let _ = events.send(Event::Error(format!("Invalid peer endpoint ID: {error}")));
                                continue;
                            }
                        };

                        match endpoint.connect(peer, wire::ALPN).await {
                            Ok(connection) => {
                                let id = next_session_id;
                                next_session_id = next_session_id.wrapping_add(1);
                                match start_session(
                                    id,
                                    connection,
                                    true,
                                    &endpoint_id,
                                    &local_name,
                                    local_avatar_data.as_deref(),
                                    internal_tx.clone(),
                                    events.clone(),
                                ).await {
                                    Ok(new_session) => {
                                        session = Some(new_session);
                                        let _ = events.send(Event::Connected);
                                    }
                                    Err(error) => {
                                        let _ = events.send(Event::Error(format!("Unable to open Landline stream: {error}")));
                                        let _ = events.send(Event::Disconnected);
                                    }
                                }
                            }
                            Err(error) => {
                                let _ = events.send(Event::Error(format!("Unable to connect: {error}")));
                                let _ = events.send(Event::Disconnected);
                            }
                        }
                    }
                    Command::Disconnect => {
                        close_session(&mut session);
                        let _ = events.send(Event::Disconnected);
                    }
                    Command::BeginTransmit => {
                        send_frame(&session, Kind::PttBegin, &[], &events);
                    }
                    Command::Audio(packet) => {
                        send_frame(&session, Kind::Audio, &packet, &events);
                    }
                    Command::EndTransmit => {
                        send_frame(&session, Kind::PttEnd, &[], &events);
                    }
                    Command::SetProfile { name, avatar_data } => {
                        local_name = normalize_name(&name);
                        local_avatar_data = avatar_data;
                        if let Ok(payload) = hello_payload(&endpoint_id, &local_name, local_avatar_data.as_deref()) {
                            send_frame(&session, Kind::Hello, &payload, &events);
                        }
                    }
                    Command::Shutdown => break,
                }
            }
            internal = internal_rx.recv() => {
                let Some(internal) = internal else { break; };
                match internal {
                    Internal::Incoming(connection) => {
                        close_session(&mut session);
                        let id = next_session_id;
                        next_session_id = next_session_id.wrapping_add(1);
                        match start_session(
                            id,
                            connection,
                            false,
                            &endpoint_id,
                            &local_name,
                            local_avatar_data.as_deref(),
                            internal_tx.clone(),
                            events.clone(),
                        ).await {
                            Ok(new_session) => {
                                session = Some(new_session);
                                let _ = events.send(Event::Connected);
                            }
                            Err(error) => {
                                let _ = events.send(Event::Error(format!("Unable to accept Landline stream: {error}")));
                            }
                        }
                    }
                    Internal::AcceptError(error) => {
                        tracing::warn!(%error, "Iroh incoming connection failed");
                    }
                    Internal::SessionEnded { id, error } => {
                        let is_current = session.as_ref().is_some_and(|active| active.id == id);
                        if is_current {
                            session = None;
                            if let Some(error) = error {
                                let _ = events.send(Event::Error(error));
                            }
                            let _ = events.send(Event::RemoteTransmit(false));
                            let _ = events.send(Event::Disconnected);
                        }
                    }
                }
            }
        }
    }

    close_session(&mut session);
    accept_task.abort();
    endpoint.close().await;
    Ok(())
}

fn close_session(session: &mut Option<Session>) {
    if let Some(active) = session.take() {
        active.task.abort();
    }
}

fn send_frame(session: &Option<Session>, kind: Kind, payload: &[u8], events: &mpsc::Sender<Event>) {
    let Some(session) = session else { return; };
    match wire::encode(kind, payload) {
        Ok(frame) => {
            if session.frames.send(frame).is_err() {
                let _ = events.send(Event::Error("Landline connection is no longer writable".into()));
            }
        }
        Err(error) => {
            let _ = events.send(Event::Error(error.to_string()));
        }
    }
}

async fn start_session(
    id: u64,
    connection: Connection,
    outgoing: bool,
    endpoint_id: &str,
    local_name: &str,
    local_avatar_data: Option<&str>,
    internal: tokio_mpsc::UnboundedSender<Internal>,
    events: mpsc::Sender<Event>,
) -> Result<Session> {
    let (mut send, mut recv) = if outgoing {
        connection.open_bi().await?
    } else {
        connection.accept_bi().await?
    };

    let hello = wire::encode(Kind::Hello, &hello_payload(endpoint_id, local_name, local_avatar_data)?)?;
    send.write_all(&hello).await?;

    let (frame_tx, mut frame_rx) = tokio_mpsc::unbounded_channel::<Vec<u8>>();
    let task = tokio::spawn(async move {
        let result: Result<()> = async {
            loop {
                tokio::select! {
                    outgoing = frame_rx.recv() => {
                        let Some(frame) = outgoing else { break; };
                        send.write_all(&frame).await?;
                    }
                    incoming = wire::read(&mut recv) => {
                        let frame = incoming?;
                        match frame.kind {
                            Kind::Hello => {
                                if let Ok(hello) = serde_json::from_slice::<HelloMessage>(&frame.payload) {
                                    let avatar_data = if hello.avatar_kind == "jpeg" {
                                        hello.avatar_data
                                    } else {
                                        None
                                    };
                                    let _ = events.send(Event::Peer {
                                        id: hello.endpoint_id,
                                        name: normalize_name(&hello.name),
                                        avatar_data,
                                    });
                                }
                            }
                            Kind::PttBegin => {
                                let _ = events.send(Event::RemoteTransmit(true));
                            }
                            Kind::Audio => {
                                let _ = events.send(Event::RemoteAudio(frame.payload));
                            }
                            Kind::PttEnd => {
                                let _ = events.send(Event::RemoteTransmit(false));
                            }
                            Kind::Ping => {
                                let pong = wire::encode(Kind::Pong, &frame.payload)?;
                                send.write_all(&pong).await?;
                            }
                            Kind::Pong => {}
                        }
                    }
                }
            }
            Ok(())
        }.await;

        let _ = internal.send(Internal::SessionEnded {
            id,
            error: result.err().map(|error| format!("Landline connection ended: {error}")),
        });
        drop(connection);
    });

    Ok(Session {
        id,
        frames: frame_tx,
        task,
    })
}

fn hello_payload(endpoint_id: &str, name: &str, avatar_data: Option<&str>) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec(&HelloMessage {
        endpoint_id: endpoint_id.to_string(),
        name: normalize_name(name),
        avatar_kind: if avatar_data.is_some() { "jpeg".into() } else { "default".into() },
        avatar_data: avatar_data.map(ToOwned::to_owned),
    })?)
}

fn normalize_name(name: &str) -> String {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        "Caller".into()
    } else {
        trimmed.chars().take(48).collect()
    }
}

fn key_path() -> Result<PathBuf> {
    let root = dirs::data_local_dir().context("unable to find the local data directory")?;
    Ok(root.join("landline").join("iroh-secret.key"))
}

fn load_or_create_secret() -> Result<SecretKey> {
    let path = key_path()?;
    if let Ok(bytes) = fs::read(&path) {
        if let Ok(raw) = <[u8; 32]>::try_from(bytes.as_slice()) {
            return Ok(SecretKey::from_bytes(&raw));
        }
    }

    let secret = SecretKey::generate();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, secret.to_bytes())?;
    Ok(secret)
}
