use anyhow::{bail, Result};
use iroh::endpoint::RecvStream;

pub const ALPN: &[u8] = b"landline-iroh-audio/1";
pub const HEADER_SIZE: usize = 5;
pub const MAX_PAYLOAD_SIZE: usize = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Kind {
    Hello = 1,
    PttBegin = 2,
    Audio = 3,
    PttEnd = 4,
    Ping = 5,
    Pong = 6,
}

impl TryFrom<u8> for Kind {
    type Error = anyhow::Error;

    fn try_from(value: u8) -> Result<Self> {
        match value {
            1 => Ok(Self::Hello),
            2 => Ok(Self::PttBegin),
            3 => Ok(Self::Audio),
            4 => Ok(Self::PttEnd),
            5 => Ok(Self::Ping),
            6 => Ok(Self::Pong),
            _ => bail!("unknown Landline frame kind {value}"),
        }
    }
}

#[derive(Debug)]
pub struct Frame {
    pub kind: Kind,
    pub payload: Vec<u8>,
}

pub fn encode(kind: Kind, payload: &[u8]) -> Result<Vec<u8>> {
    if payload.len() > MAX_PAYLOAD_SIZE {
        bail!("Landline payload too large: {} bytes", payload.len());
    }

    let mut out = Vec::with_capacity(HEADER_SIZE + payload.len());
    out.push(kind as u8);
    out.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    out.extend_from_slice(payload);
    Ok(out)
}

pub async fn read(recv: &mut RecvStream) -> Result<Frame> {
    let mut header = [0_u8; HEADER_SIZE];
    recv.read_exact(&mut header).await?;

    let kind = Kind::try_from(header[0])?;
    let len = u32::from_le_bytes([header[1], header[2], header[3], header[4]]) as usize;
    if len > MAX_PAYLOAD_SIZE {
        bail!("Landline payload too large: {len} bytes");
    }

    let mut payload = vec![0_u8; len];
    if len > 0 {
        recv.read_exact(&mut payload).await?;
    }
    Ok(Frame { kind, payload })
}
