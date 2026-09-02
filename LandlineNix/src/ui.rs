use std::{fs, path::PathBuf, time::{Duration, Instant}};

use eframe::egui::{
    self, Align2, Color32, FontId, Id, PointerButton, Pos2, Rect, Sense, Stroke, Vec2,
    ViewportCommand, pos2, vec2,
};
use serde::{Deserialize, Serialize};

use crate::{
    audio::{Capture, Playback},
    network::{self, Command, Event},
};

const DESIGN_SIZE: Vec2 = Vec2::new(320.0, 672.0);
const PANEL: Color32 = Color32::from_rgb(20, 22, 21);
const PANEL_SOFT: Color32 = Color32::from_rgb(33, 34, 34);
const INACTIVE: Color32 = Color32::from_rgb(120, 125, 120);
const GREEN: Color32 = Color32::from_rgb(5, 191, 56);
const RED: Color32 = Color32::from_rgb(255, 87, 84);
const VU_GREEN: Color32 = Color32::from_rgb(23, 178, 57);
const VU_ORANGE: Color32 = Color32::from_rgb(255, 150, 1);
const VU_RED: Color32 = Color32::from_rgb(255, 97, 87);
const TEXT_SOFT: Color32 = Color32::from_rgb(217, 217, 217);

#[derive(Debug, Serialize, Deserialize)]
struct StoredProfile {
    name: String,
}

pub struct LandlineApp {
    network: network::Handle,
    playback: Option<Playback>,
    capture: Option<Capture>,
    endpoint_id: String,
    peer_input: String,
    connected: bool,
    peer_id: String,
    peer_name: String,
    remote_talking: bool,
    local_talking: bool,
    ptt_was_down: bool,
    volume: f32,
    meter_level: f32,
    error: Option<String>,
    show_settings: bool,
    show_profile: bool,
    profile_name: String,
    draft_name: String,
    animation_epoch: Instant,
}

impl LandlineApp {
    pub fn new(_cc: &eframe::CreationContext<'_>) -> Self {
        let profile_name = load_profile_name();
        let network = network::Handle::spawn(profile_name.clone());
        let playback = Playback::new().map_err(|error| {
            tracing::warn!(%error, "audio playback unavailable at startup");
            error
        }).ok();
        if let Some(playback) = &playback {
            playback.set_volume(0.25);
        }

        Self {
            network,
            playback,
            capture: None,
            endpoint_id: String::new(),
            peer_input: String::new(),
            connected: false,
            peer_id: String::new(),
            peer_name: String::new(),
            remote_talking: false,
            local_talking: false,
            ptt_was_down: false,
            volume: 0.25,
            meter_level: 0.0,
            error: None,
            show_settings: false,
            show_profile: false,
            profile_name: profile_name.clone(),
            draft_name: profile_name,
            animation_epoch: Instant::now(),
        }
    }

    fn poll_network(&mut self) {
        while let Ok(event) = self.network.events.try_recv() {
            match event {
                Event::EndpointReady(id) => self.endpoint_id = id,
                Event::Connected => {
                    self.connected = true;
                    self.error = None;
                }
                Event::Disconnected => {
                    self.connected = false;
                    self.remote_talking = false;
                    self.peer_id.clear();
                    self.peer_name.clear();
                    self.stop_transmit();
                }
                Event::Peer { id, name } => {
                    self.peer_id = id;
                    self.peer_name = name;
                }
                Event::RemoteTransmit(active) => self.remote_talking = active,
                Event::RemoteAudio(packet) => {
                    if let Some(playback) = &self.playback {
                        if let Err(error) = playback.enqueue_network_packet(&packet) {
                            tracing::warn!(%error, "invalid remote audio packet");
                        }
                    }
                }
                Event::Error(error) => self.error = Some(error),
            }
        }
    }

    fn begin_transmit(&mut self) {
        if !self.connected || self.remote_talking || self.local_talking {
            return;
        }

        match Capture::start() {
            Ok(capture) => {
                self.capture = Some(capture);
                self.local_talking = true;
                let _ = self.network.commands.send(Command::BeginTransmit);
                self.error = None;
            }
            Err(error) => {
                self.error = Some(format!("Microphone unavailable: {error}"));
            }
        }
    }

    fn stop_transmit(&mut self) {
        if self.local_talking {
            let _ = self.network.commands.send(Command::EndTransmit);
        }
        self.capture = None;
        self.local_talking = false;
        self.meter_level = 0.0;
    }

    fn pump_audio(&mut self) {
        if let Some(capture) = &self.capture {
            let sample = capture.level();
            if sample >= self.meter_level {
                self.meter_level = self.meter_level * 0.20 + sample * 0.80;
            } else {
                self.meter_level = self.meter_level * 0.72 + sample * 0.28;
            }
            if self.meter_level < 0.01 {
                self.meter_level = 0.0;
            }

            for packet in capture.drain_packets() {
                let _ = self.network.commands.send(Command::Audio(packet));
            }
        }
    }

    fn status_text(&self, ptt_hovered: bool, remote_hovered: bool) -> String {
        if let Some(error) = &self.error {
            return error.clone();
        }
        if self.local_talking {
            return "You are talking".into();
        }
        if self.remote_talking {
            return format!("{} is talking", self.remote_display_name());
        }
        if remote_hovered && self.connected {
            return format!("{} is online", self.remote_display_name());
        }
        if ptt_hovered {
            return if self.connected { "Click to talk" } else { "Connect a peer to talk" }.into();
        }
        if self.connected {
            "You are muted".into()
        } else {
            "Ready — open LANDLINE to connect".into()
        }
    }

    fn remote_display_name(&self) -> &str {
        if self.peer_name.trim().is_empty() { "Caller" } else { &self.peer_name }
    }

    fn save_profile(&mut self) {
        let name = normalize_name(&self.draft_name);
        self.profile_name = name.clone();
        self.draft_name = name.clone();
        if let Err(error) = save_profile_name(&name) {
            self.error = Some(format!("Could not save profile: {error}"));
        }
        let _ = self.network.commands.send(Command::SetName(name));
        self.show_profile = false;
    }

    fn paint_window_controls(&mut self, ui: &mut egui::Ui, canvas: Rect) {
        let painter = ui.painter();
        let backing = design_rect(canvas, 24.0, 24.0, 64.0, 24.0);
        painter.rect_filled(backing, 8.0, Color32::from_black_alpha(51));

        let centers = [36.0, 56.0, 76.0];
        let symbols = [ControlSymbol::Minimize, ControlSymbol::Maximize, ControlSymbol::Close];
        for (index, (&x, symbol)) in centers.iter().zip(symbols).enumerate() {
            let center = canvas.min + vec2(x, 36.0);
            let hit = Rect::from_center_size(center, vec2(18.0, 18.0));
            let response = ui.interact(hit, Id::new(("linux-window-control", index)), Sense::click());
            let fill = if response.hovered() {
                Color32::from_rgb(235, 235, 235)
            } else {
                Color32::from_rgb(190, 190, 190)
            };
            painter.circle_filled(center, 6.0, fill);
            paint_control_symbol(painter, center, symbol, Color32::from_rgb(45, 45, 45));

            if response.clicked() {
                match symbol {
                    ControlSymbol::Minimize => ui.send_viewport_cmd(ViewportCommand::Minimized(true)),
                    ControlSymbol::Maximize => {
                        let maximized = ui.input(|input| input.viewport().maximized.unwrap_or(false));
                        ui.send_viewport_cmd(ViewportCommand::Maximized(!maximized));
                    }
                    ControlSymbol::Close => ui.send_viewport_cmd(ViewportCommand::Close),
                }
            }
        }
    }

    fn paint_top_bar(&mut self, ui: &mut egui::Ui, canvas: Rect) {
        let painter = ui.painter();
        let title_rect = design_rect(canvas, 104.0, 24.0, 152.0, 24.0);
        painter.text(
            title_rect.center(),
            Align2::CENTER_CENTER,
            "LANDLINE",
            FontId::proportional(14.0),
            Color32::WHITE,
        );
        painter.line_segment(
            [pos2(title_rect.left() + 8.0, title_rect.bottom() - 3.0), pos2(title_rect.right() - 8.0, title_rect.bottom() - 3.0)],
            Stroke::new(1.0, Color32::from_gray(145)),
        );

        let title_response = ui.interact(title_rect, Id::new("title-drag-settings"), Sense::click_and_drag());
        if title_response.drag_started_by(PointerButton::Primary) {
            ui.send_viewport_cmd(ViewportCommand::StartDrag);
        }
        if title_response.clicked() {
            self.show_settings = !self.show_settings;
            self.show_profile = false;
        }

        let profile_rect = design_rect(canvas, 272.0, 24.0, 24.0, 24.0);
        let profile_response = ui.interact(profile_rect, Id::new("profile-button"), Sense::click());
        let scale = if profile_response.hovered() { 1.05 } else { 1.0 };
        let icon_rect = Rect::from_center_size(profile_rect.center(), profile_rect.size() * scale);
        painter.circle_stroke(icon_rect.center(), 11.0 * scale, Stroke::new(1.4, Color32::WHITE));
        painter.circle_filled(icon_rect.center() - vec2(0.0, 3.5), 3.2 * scale, Color32::WHITE);
        painter.rect_filled(
            Rect::from_center_size(icon_rect.center() + vec2(0.0, 4.2), vec2(9.0, 5.0) * scale),
            3.0,
            Color32::WHITE,
        );
        if profile_response.clicked() {
            self.draft_name = self.profile_name.clone();
            self.show_profile = true;
            self.show_settings = false;
        }
    }

    fn paint_radio(&mut self, ui: &mut egui::Ui, canvas: Rect) -> (bool, bool) {
        let painter = ui.painter();
        let radio = design_rect(canvas, 24.0, 96.0, 272.0, 272.0);
        painter.circle_filled(radio.center(), 136.0, PANEL);

        let dial_center = radio.center();
        let mut remote_hovered = false;
        for index in 0..8 {
            let angle = (index as f32 / 8.0) * std::f32::consts::TAU - std::f32::consts::FRAC_PI_2;
            let center = dial_center + vec2(angle.cos() * 88.0, angle.sin() * 88.0);
            let avatar_rect = Rect::from_center_size(center, vec2(48.0, 48.0));

            if index == 0 {
                painter.circle_filled(center, 24.0, Color32::from_rgb(64, 77, 79));
                paint_initials(painter, center, &self.profile_name, Color32::WHITE);
                if self.local_talking {
                    self.paint_talking_badge(painter, center + vec2(20.0, 20.0));
                }
            } else if index == 1 && self.connected && !self.peer_name.is_empty() {
                let response = ui.interact(avatar_rect, Id::new("remote-avatar"), Sense::hover());
                remote_hovered = response.hovered();
                painter.circle_filled(center, 24.0, Color32::from_rgb(64, 77, 79));
                paint_initials(painter, center, self.remote_display_name(), Color32::WHITE);
                if self.remote_talking && !self.local_talking {
                    self.paint_talking_badge(painter, center + vec2(20.0, 20.0));
                }
            } else {
                painter.circle_filled(center, 24.0, Color32::BLACK);
            }
        }

        let ptt_center = dial_center;
        let ptt_rect = Rect::from_center_size(ptt_center, vec2(88.0, 88.0));
        let ptt_response = ui.interact(ptt_rect, Id::new("ptt"), Sense::click_and_drag());
        let ptt_down = ptt_response.is_pointer_button_down_on();
        if ptt_down != self.ptt_was_down {
            self.ptt_was_down = ptt_down;
            if ptt_down {
                self.begin_transmit();
            } else {
                self.stop_transmit();
            }
        }

        let scale = if ptt_response.hovered() || ptt_down || self.local_talking { 1.04 } else { 1.0 };
        painter.circle_filled(ptt_center, 40.0 * scale, if self.local_talking { GREEN } else { RED });
        painter.text(
            ptt_center,
            Align2::CENTER_CENTER,
            if self.local_talking { "ON" } else { "MIC" },
            FontId::proportional(12.0),
            Color32::from_black_alpha(210),
        );

        (ptt_response.hovered(), remote_hovered)
    }

    fn paint_talking_badge(&self, painter: &egui::Painter, center: Pos2) {
        painter.circle_filled(center, 12.0, GREEN);
        let phase = (self.animation_epoch.elapsed().as_secs_f32() * 3.0).sin() * 0.5 + 0.5;
        let a = [7.0, 13.0, 10.0, 6.0];
        let b = [12.0, 7.0, 14.0, 9.0];
        for index in 0..4 {
            let height = a[index] * phase + b[index] * (1.0 - phase);
            let x = center.x - 6.0 + index as f32 * 4.0;
            painter.line_segment(
                [pos2(x, center.y - height / 2.0), pos2(x, center.y + height / 2.0)],
                Stroke::new(2.0, Color32::from_black_alpha(205)),
            );
        }
    }

    fn paint_status(&self, ui: &mut egui::Ui, canvas: Rect, ptt_hovered: bool, remote_hovered: bool) {
        let painter = ui.painter();
        let rect = design_rect(canvas, 24.0, 408.0, 272.0, 48.0);
        painter.rect_filled(rect, 16.0, PANEL);
        painter.circle_filled(rect.min + vec2(20.0, 24.0), 4.0, if self.connected { GREEN } else { INACTIVE });
        painter.text(
            rect.min + vec2(37.0, 24.0),
            Align2::LEFT_CENTER,
            self.status_text(ptt_hovered, remote_hovered),
            FontId::proportional(10.0),
            TEXT_SOFT,
        );
    }

    fn paint_volume(&mut self, ui: &mut egui::Ui, canvas: Rect) {
        let painter = ui.painter();
        let panel = design_rect(canvas, 24.0, 472.0, 272.0, 80.0);
        painter.rect_filled(panel, 16.0, PANEL);
        painter.text(panel.min + vec2(25.0, 19.0), Align2::LEFT_CENTER, "Volume", FontId::proportional(13.0), Color32::WHITE);
        painter.text(panel.min + vec2(224.0, 19.0), Align2::RIGHT_CENTER, format!("{}", (self.volume * 100.0).round() as i32), FontId::proportional(13.0), Color32::WHITE);

        let slider = design_rect(canvas, 47.0, 504.0, 225.0, 24.0);
        let response = ui.interact(slider, Id::new("volume-slider"), Sense::click_and_drag());
        if (response.dragged() || response.clicked()) && let Some(pointer) = response.interact_pointer_pos() {
            self.volume = ((pointer.x - slider.left() - 12.0) / 201.0).clamp(0.0, 1.0);
            if let Some(playback) = &self.playback {
                playback.set_volume(self.volume);
            }
        }

        let track = Rect::from_min_size(slider.min + vec2(1.0, 8.0), vec2(224.0, 8.0));
        painter.rect_filled(track, 4.0, Color32::from_black_alpha(235));
        let knob_x = slider.left() + 201.0 * self.volume;
        let fill = Rect::from_min_max(track.min, pos2((knob_x + 12.0).min(track.right()), track.bottom()));
        painter.rect_filled(fill, 4.0, GREEN);
        painter.circle_filled(pos2(knob_x + 12.0, slider.center().y), 12.0, Color32::WHITE);
        painter.circle_filled(pos2(knob_x + 12.0, slider.center().y), 6.0, GREEN);
    }

    fn paint_vu(&self, ui: &mut egui::Ui, canvas: Rect) {
        let painter = ui.painter();
        let panel = design_rect(canvas, 24.0, 568.0, 272.0, 80.0);
        painter.rect_filled(panel, 16.0, PANEL);
        let start_x = panel.left() + 12.0;
        for index in 0..16 {
            let x = start_x + index as f32 * 16.0;
            let rect = Rect::from_min_size(pos2(x, panel.top() + 12.0), vec2(8.0, 56.0));
            let threshold = (index + 1) as f32 / 16.0;
            let active = threshold <= self.meter_level;
            let color = if !active {
                INACTIVE
            } else if index <= 9 {
                VU_GREEN
            } else if index <= 12 {
                VU_ORANGE
            } else {
                VU_RED
            };
            painter.rect_filled(rect, 4.0, color);
        }
    }

    fn paint_profile_sheet(&mut self, ui: &mut egui::Ui, canvas: Rect) {
        let sheet = design_rect(canvas, 0.0, 88.0, 320.0, 584.0);
        ui.painter().rect_filled(sheet, 16.0, Color32::from_rgba_unmultiplied(255, 255, 255, 246));
        ui.allocate_ui_at_rect(sheet.shrink2(vec2(24.0, 20.0)), |ui| {
            ui.visuals_mut().override_text_color = Some(Color32::from_rgb(23, 23, 23));
            ui.heading("Edit profile");
            ui.add_space(22.0);
            ui.label("Name");
            ui.add_sized([272.0, 48.0], egui::TextEdit::singleline(&mut self.draft_name).hint_text("Random Caller"));
            ui.add_space(24.0);
            ui.label("Avatar");
            ui.add_space(8.0);
            let avatar = ui.allocate_response(vec2(272.0, 208.0), Sense::hover());
            ui.painter().rect_filled(avatar.rect, 16.0, Color32::from_rgb(243, 243, 243));
            ui.painter().text(avatar.rect.center(), Align2::CENTER_CENTER, "Avatar image support\ncomes next", FontId::proportional(13.0), Color32::from_gray(107));
            ui.add_space(16.0);
            if ui.add_sized([272.0, 48.0], egui::Button::new("Update")).clicked() {
                self.save_profile();
            }
        });

        let close_rect = Rect::from_min_size(sheet.min + vec2(280.0, 8.0), vec2(32.0, 32.0));
        if ui.interact(close_rect, Id::new("profile-close"), Sense::click()).clicked() {
            self.show_profile = false;
        }
        ui.painter().text(close_rect.center(), Align2::CENTER_CENTER, "×", FontId::proportional(20.0), Color32::from_rgb(23, 23, 23));
    }

    fn paint_settings_sheet(&mut self, ui: &mut egui::Ui, canvas: Rect) {
        let sheet = design_rect(canvas, 0.0, 88.0, 320.0, 584.0);
        ui.painter().rect_filled(sheet, 16.0, Color32::from_rgba_unmultiplied(255, 255, 255, 246));
        ui.allocate_ui_at_rect(sheet.shrink2(vec2(24.0, 20.0)), |ui| {
            ui.visuals_mut().override_text_color = Some(Color32::from_rgb(23, 23, 23));
            ui.heading("Iroh connection");
            ui.add_space(18.0);
            ui.label("This NixOS endpoint ID");
            let mut own_id = self.endpoint_id.clone();
            ui.add_sized([272.0, 64.0], egui::TextEdit::multiline(&mut own_id).interactive(false));
            ui.add_space(14.0);
            ui.label("Peer endpoint ID");
            ui.add_sized([272.0, 64.0], egui::TextEdit::multiline(&mut self.peer_input));
            ui.add_space(12.0);
            let label = if self.connected { "Disconnect" } else { "Connect" };
            if ui.add_sized([272.0, 48.0], egui::Button::new(label)).clicked() {
                if self.connected {
                    let _ = self.network.commands.send(Command::Disconnect);
                } else {
                    let _ = self.network.commands.send(Command::Connect(self.peer_input.clone()));
                    self.error = None;
                }
            }
            ui.add_space(20.0);
            ui.label(format!("State: {}", if self.connected { "Connected" } else { "Waiting" }));
            if !self.peer_name.is_empty() {
                ui.label(format!("Peer: {}", self.peer_name));
            }
            ui.add_space(18.0);
            ui.small("Click and drag the LANDLINE wordmark to move the window. Click it without dragging to open or close this panel.");
        });

        let close_rect = Rect::from_min_size(sheet.min + vec2(280.0, 8.0), vec2(32.0, 32.0));
        if ui.interact(close_rect, Id::new("settings-close"), Sense::click()).clicked() {
            self.show_settings = false;
        }
        ui.painter().text(close_rect.center(), Align2::CENTER_CENTER, "×", FontId::proportional(20.0), Color32::from_rgb(23, 23, 23));
    }
}

impl Drop for LandlineApp {
    fn drop(&mut self) {
        self.stop_transmit();
        let _ = self.network.commands.send(Command::Shutdown);
    }
}

impl eframe::App for LandlineApp {
    fn clear_color(&self, _visuals: &egui::Visuals) -> [f32; 4] {
        egui::Rgba::TRANSPARENT.to_array()
    }

    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.poll_network();
        self.pump_audio();
        ctx.request_repaint_after(Duration::from_millis(33));

        egui::CentralPanel::default().frame(egui::Frame::NONE).show(ctx, |ui| {
            let available = ui.max_rect();
            let canvas = Rect::from_center_size(available.center(), DESIGN_SIZE);
            ui.painter().rect_filled(canvas, 24.0, Color32::from_rgba_unmultiplied(171, 171, 171, 205));

            self.paint_window_controls(ui, canvas);
            self.paint_top_bar(ui, canvas);
            let (ptt_hovered, remote_hovered) = self.paint_radio(ui, canvas);
            self.paint_status(ui, canvas, ptt_hovered, remote_hovered);
            self.paint_volume(ui, canvas);
            self.paint_vu(ui, canvas);

            if self.show_profile {
                self.paint_profile_sheet(ui, canvas);
            } else if self.show_settings {
                self.paint_settings_sheet(ui, canvas);
            }
        });
    }
}

#[derive(Clone, Copy)]
enum ControlSymbol { Minimize, Maximize, Close }

fn paint_control_symbol(painter: &egui::Painter, center: Pos2, symbol: ControlSymbol, color: Color32) {
    match symbol {
        ControlSymbol::Minimize => painter.line_segment([center + vec2(-3.0, 1.5), center + vec2(3.0, 1.5)], Stroke::new(1.0, color)),
        ControlSymbol::Maximize => painter.rect_stroke(Rect::from_center_size(center, vec2(6.0, 6.0)), 0.5, Stroke::new(1.0, color), egui::StrokeKind::Inside),
        ControlSymbol::Close => {
            painter.line_segment([center + vec2(-2.5, -2.5), center + vec2(2.5, 2.5)], Stroke::new(1.0, color));
            painter.line_segment([center + vec2(2.5, -2.5), center + vec2(-2.5, 2.5)], Stroke::new(1.0, color))
        }
    };
}

fn paint_initials(painter: &egui::Painter, center: Pos2, name: &str, color: Color32) {
    let initials: String = name.split_whitespace().filter_map(|word| word.chars().next()).take(2).collect::<String>().to_uppercase();
    painter.text(center, Align2::CENTER_CENTER, if initials.is_empty() { "C" } else { &initials }, FontId::proportional(14.0), color);
}

fn design_rect(canvas: Rect, x: f32, y: f32, width: f32, height: f32) -> Rect {
    Rect::from_min_size(canvas.min + vec2(x, y), vec2(width, height))
}

fn normalize_name(name: &str) -> String {
    let trimmed = name.trim();
    if trimmed.is_empty() { "Caller".into() } else { trimmed.chars().take(48).collect() }
}

fn profile_path() -> Option<PathBuf> {
    dirs::config_dir().map(|root| root.join("landline").join("profile.json"))
}

fn load_profile_name() -> String {
    let Some(path) = profile_path() else { return "Caller".into(); };
    fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<StoredProfile>(&bytes).ok())
        .map(|profile| normalize_name(&profile.name))
        .unwrap_or_else(|| "Caller".into())
}

fn save_profile_name(name: &str) -> anyhow::Result<()> {
    let path = profile_path().ok_or_else(|| anyhow::anyhow!("configuration directory unavailable"))?;
    if let Some(parent) = path.parent() { fs::create_dir_all(parent)?; }
    fs::write(path, serde_json::to_vec_pretty(&StoredProfile { name: normalize_name(name) })?)?;
    Ok(())
}
