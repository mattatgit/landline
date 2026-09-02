use std::sync::{
    atomic::{AtomicU32, Ordering},
    mpsc::{self, Receiver, SyncSender},
    Arc,
};

use anyhow::{bail, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleFormat, Stream};
use rodio::{buffer::SamplesBuffer, OutputStream, Sink};

const MAX_QUEUED_PACKETS: usize = 12;

pub struct Capture {
    _stream: Stream,
    packets: Receiver<Vec<u8>>,
    level_bits: Arc<AtomicU32>,
}

impl Capture {
    pub fn start() -> Result<Self> {
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .context("no microphone input device is available")?;
        let supported = device.default_input_config()?;
        let sample_format = supported.sample_format();
        let config: cpal::StreamConfig = supported.into();
        let channels = usize::from(config.channels.max(1));
        let sample_rate = config.sample_rate.0;

        let (tx, rx) = mpsc::sync_channel(MAX_QUEUED_PACKETS);
        let level_bits = Arc::new(AtomicU32::new(0_f32.to_bits()));
        let error_callback = |error| tracing::warn!(%error, "microphone stream error");

        let stream = match sample_format {
            SampleFormat::F32 => {
                let tx = tx.clone();
                let level = level_bits.clone();
                device.build_input_stream(
                    &config,
                    move |data: &[f32], _| push_f32(data, channels, sample_rate, &tx, &level),
                    error_callback,
                    None,
                )?
            }
            SampleFormat::I16 => {
                let tx = tx.clone();
                let level = level_bits.clone();
                device.build_input_stream(
                    &config,
                    move |data: &[i16], _| {
                        let converted: Vec<f32> = data.iter().map(|&s| s as f32 / 32768.0).collect();
                        push_f32(&converted, channels, sample_rate, &tx, &level);
                    },
                    error_callback,
                    None,
                )?
            }
            SampleFormat::U16 => {
                let tx = tx.clone();
                let level = level_bits.clone();
                device.build_input_stream(
                    &config,
                    move |data: &[u16], _| {
                        let converted: Vec<f32> = data
                            .iter()
                            .map(|&s| (s as f32 / u16::MAX as f32) * 2.0 - 1.0)
                            .collect();
                        push_f32(&converted, channels, sample_rate, &tx, &level);
                    },
                    error_callback,
                    None,
                )?
            }
            other => bail!("unsupported microphone sample format: {other:?}"),
        };

        stream.play()?;
        Ok(Self {
            _stream: stream,
            packets: rx,
            level_bits,
        })
    }

    pub fn drain_packets(&self) -> Vec<Vec<u8>> {
        self.packets.try_iter().collect()
    }

    pub fn level(&self) -> f32 {
        f32::from_bits(self.level_bits.load(Ordering::Relaxed)).clamp(0.0, 1.0)
    }
}

fn push_f32(
    data: &[f32],
    channels: usize,
    sample_rate: u32,
    tx: &SyncSender<Vec<u8>>,
    level_bits: &AtomicU32,
) {
    if data.is_empty() || channels == 0 {
        return;
    }

    let mut mono = Vec::with_capacity(data.len() / channels);
    let mut sum_squares = 0.0_f64;

    for frame in data.chunks_exact(channels) {
        let sample = frame.iter().copied().sum::<f32>() / channels as f32;
        let sample = sample.clamp(-1.0, 1.0);
        mono.push(sample);
        sum_squares += f64::from(sample) * f64::from(sample);
    }

    if mono.is_empty() {
        return;
    }

    let rms = (sum_squares / mono.len() as f64).sqrt();
    let db = 20.0 * rms.max(0.000_001).log10();
    let normalized = ((db + 52.0) / 52.0).clamp(0.0, 1.0) as f32;
    let normalized = if normalized < 0.045 { 0.0 } else { normalized };
    level_bits.store(normalized.to_bits(), Ordering::Relaxed);

    let frame_count = mono.len() as u32;
    let mut packet = Vec::with_capacity(8 + mono.len() * 2);
    packet.extend_from_slice(&sample_rate.to_le_bytes());
    packet.extend_from_slice(&frame_count.to_le_bytes());
    for sample in mono {
        let pcm = (sample * i16::MAX as f32)
            .round()
            .clamp(i16::MIN as f32, i16::MAX as f32) as i16;
        packet.extend_from_slice(&pcm.to_le_bytes());
    }

    let _ = tx.try_send(packet);
}

pub struct Playback {
    _stream: OutputStream,
    sink: Sink,
}

impl Playback {
    pub fn new() -> Result<Self> {
        let (stream, handle) = OutputStream::try_default().context("no audio output device is available")?;
        let sink = Sink::try_new(&handle)?;
        sink.set_volume(0.25);
        Ok(Self {
            _stream: stream,
            sink,
        })
    }

    pub fn set_volume(&self, volume: f32) {
        self.sink.set_volume(volume.clamp(0.0, 1.0));
    }

    pub fn enqueue_network_packet(&self, packet: &[u8]) -> Result<()> {
        if packet.len() < 8 {
            bail!("audio packet is shorter than the Landline header");
        }

        let sample_rate = u32::from_le_bytes(packet[0..4].try_into().unwrap());
        let frame_count = u32::from_le_bytes(packet[4..8].try_into().unwrap()) as usize;
        if sample_rate == 0 {
            bail!("audio packet has a zero sample rate");
        }

        let available_frames = (packet.len() - 8) / 2;
        let count = frame_count.min(available_frames);
        let mut samples = Vec::with_capacity(count);
        for bytes in packet[8..].chunks_exact(2).take(count) {
            let pcm = i16::from_le_bytes([bytes[0], bytes[1]]);
            samples.push(pcm as f32 / 32768.0);
        }

        if !samples.is_empty() {
            self.sink.append(SamplesBuffer::new(1, sample_rate, samples));
        }
        Ok(())
    }
}
