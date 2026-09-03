from pathlib import Path

root = Path('.')

# Dependencies: native portal file picker, image processing and profile avatar encoding.
cargo = root / 'LandlineNix/Cargo.toml'
text = cargo.read_text()
if 'base64 = ' not in text:
    text = text.replace('anyhow = "1"\n', 'anyhow = "1"\nbase64 = "0.22"\n')
if '\nimage = ' not in text:
    text = text.replace('iroh = "=1.0.2"\n', 'iroh = "=1.0.2"\nimage = { version = "0.25", default-features = false, features = ["jpeg", "png"] }\n')
if '\nrfd = ' not in text:
    text = text.replace('rodio = "0.20.1"\n', 'rodio = "0.20.1"\nrfd = { version = "0.15.4", default-features = false, features = ["xdg-portal", "tokio"] }\n')
cargo.write_text(text)

# Network profile parity: include optional JPEG avatar data in hello messages.
network = root / 'LandlineNix/src/network.rs'
text = network.read_text()
text = text.replace('    SetName(String),\n', '    SetProfile { name: String, avatar_data: Option<String> },\n')
text = text.replace('    pub fn spawn(name: String) -> Self {', '    pub fn spawn(name: String, avatar_data: Option<String>) -> Self {')
text = text.replace('runtime.block_on(run(command_rx, event_tx.clone(), name))', 'runtime.block_on(run(command_rx, event_tx.clone(), name, avatar_data))')
text = text.replace('    mut local_name: String,\n) -> Result<()> {', '    mut local_name: String,\n    mut local_avatar_data: Option<String>,\n) -> Result<()> {')
text = text.replace('                                    &endpoint_id,\n                                    &local_name,\n                                    internal_tx.clone(),', '                                    &endpoint_id,\n                                    &local_name,\n                                    local_avatar_data.as_deref(),\n                                    internal_tx.clone(),')
text = text.replace('                            &endpoint_id,\n                            &local_name,\n                            internal_tx.clone(),', '                            &endpoint_id,\n                            &local_name,\n                            local_avatar_data.as_deref(),\n                            internal_tx.clone(),')
old = '''                    Command::SetName(name) => {
                        local_name = normalize_name(&name);
                        if let Ok(payload) = hello_payload(&endpoint_id, &local_name) {
                            send_frame(&session, Kind::Hello, &payload, &events);
                        }
                    }
'''
new = '''                    Command::SetProfile { name, avatar_data } => {
                        local_name = normalize_name(&name);
                        local_avatar_data = avatar_data;
                        if let Ok(payload) = hello_payload(&endpoint_id, &local_name, local_avatar_data.as_deref()) {
                            send_frame(&session, Kind::Hello, &payload, &events);
                        }
                    }
'''
if old not in text:
    raise SystemExit('SetName block not found')
text = text.replace(old, new)
text = text.replace('    local_name: &str,\n    internal:', '    local_name: &str,\n    local_avatar_data: Option<&str>,\n    internal:')
text = text.replace('let hello = wire::encode(Kind::Hello, &hello_payload(endpoint_id, local_name)?)?;', 'let hello = wire::encode(Kind::Hello, &hello_payload(endpoint_id, local_name, local_avatar_data)?)?;')
old = '''fn hello_payload(endpoint_id: &str, name: &str) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec(&HelloMessage {
        endpoint_id: endpoint_id.to_string(),
        name: normalize_name(name),
        avatar_kind: "default".into(),
        avatar_data: None,
    })?)
}
'''
new = '''fn hello_payload(endpoint_id: &str, name: &str, avatar_data: Option<&str>) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec(&HelloMessage {
        endpoint_id: endpoint_id.to_string(),
        name: normalize_name(name),
        avatar_kind: if avatar_data.is_some() { "jpeg".into() } else { "default".into() },
        avatar_data: avatar_data.map(ToOwned::to_owned),
    })?)
}
'''
if old not in text:
    raise SystemExit('hello_payload block not found')
text = text.replace(old, new)
network.write_text(text)

# UI parity.
ui = root / 'LandlineNix/src/ui.rs'
text = ui.read_text()
text = text.replace(
    'use std::{fs, path::PathBuf, sync::Arc, time::{Duration, Instant}};\n',
    'use std::{fs, path::{Path, PathBuf}, sync::Arc, time::{Duration, Instant}};\n\nuse base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};\n'
)
text = text.replace(
    '    self, Align2, Color32, FontData, FontDefinitions, FontFamily, FontId, Id, PointerButton, Pos2, Rect, Sense, Stroke, Vec2,\n',
    '    self, Align2, Color32, ColorImage, FontData, FontDefinitions, FontFamily, FontId, Id, PointerButton, Pos2, Rect, Sense, Stroke, TextureHandle, TextureOptions, Vec2,\n'
)
if 'use image::imageops::FilterType;' not in text:
    text = text.replace('use serde::{Deserialize, Serialize};\n', 'use image::imageops::FilterType;\nuse serde::{Deserialize, Serialize};\n')

text = text.replace(
    '''#[derive(Debug, Serialize, Deserialize)]
struct StoredProfile {
    name: String,
}
''',
    '''#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredProfile {
    name: String,
    #[serde(default)]
    avatar_data: Option<String>,
}
'''
)
text = text.replace(
    '    show_settings: bool,\n    show_profile: bool,\n    profile_name: String,\n    draft_name: String,\n',
    '    show_settings: bool,\n    show_profile: bool,\n    show_app_menu: bool,\n    profile_name: String,\n    draft_name: String,\n    profile_avatar_data: Option<String>,\n    draft_avatar_data: Option<String>,\n    profile_avatar_texture: Option<TextureHandle>,\n    draft_avatar_texture: Option<TextureHandle>,\n'
)

old = '''        let profile_name = load_profile_name();
        let network = network::Handle::spawn(profile_name.clone());
'''
new = '''        let stored_profile = load_profile();
        let profile_name = normalize_name(&stored_profile.name);
        let profile_avatar_data = stored_profile.avatar_data.clone();
        let profile_avatar_texture = profile_avatar_data
            .as_deref()
            .and_then(|data| texture_from_avatar_data(&cc.egui_ctx, "profile-avatar", data));
        let network = network::Handle::spawn(profile_name.clone(), profile_avatar_data.clone());
'''
if old not in text:
    raise SystemExit('profile init block not found')
text = text.replace(old, new)
text = text.replace(
    '            show_settings: false,\n            show_profile: false,\n            profile_name: profile_name.clone(),\n            draft_name: profile_name,\n',
    '            show_settings: false,\n            show_profile: false,\n            show_app_menu: false,\n            profile_name: profile_name.clone(),\n            draft_name: profile_name,\n            profile_avatar_data: profile_avatar_data.clone(),\n            draft_avatar_data: profile_avatar_data,\n            profile_avatar_texture: profile_avatar_texture.clone(),\n            draft_avatar_texture: profile_avatar_texture,\n'
)

old = '''    fn save_profile(&mut self) {
        let name = normalize_name(&self.draft_name);
        self.profile_name = name.clone();
        self.draft_name = name.clone();
        if let Err(error) = save_profile_name(&name) {
            self.error = Some(format!("Could not save profile: {error}"));
        }
        let _ = self.network.commands.send(Command::SetName(name));
        self.show_profile = false;
    }
'''
new = '''    fn save_profile(&mut self) {
        let name = normalize_name(&self.draft_name);
        let avatar_data = self.draft_avatar_data.clone();
        self.profile_name = name.clone();
        self.draft_name = name.clone();
        self.profile_avatar_data = avatar_data.clone();
        self.profile_avatar_texture = self.draft_avatar_texture.clone();
        if let Err(error) = save_stored_profile(&StoredProfile { name: name.clone(), avatar_data: avatar_data.clone() }) {
            self.error = Some(format!("Could not save profile: {error}"));
        }
        let _ = self.network.commands.send(Command::SetProfile { name, avatar_data });
        self.show_profile = false;
    }

    fn load_avatar_path(&mut self, ctx: &egui::Context, path: &Path) {
        match fs::read(path) {
            Ok(bytes) => match prepare_avatar(&bytes) {
                Ok((encoded, image)) => {
                    self.draft_avatar_data = Some(encoded);
                    self.draft_avatar_texture = Some(ctx.load_texture("profile-avatar-draft", image, TextureOptions::LINEAR));
                    self.error = None;
                }
                Err(error) => self.error = Some(format!("Could not load avatar: {error}")),
            },
            Err(error) => self.error = Some(format!("Could not load avatar: {error}")),
        }
    }
'''
if old not in text:
    raise SystemExit('save_profile block not found')
text = text.replace(old, new)

text = text.replace(
    '''        if title_response.clicked() {
            self.show_settings = !self.show_settings;
            self.show_profile = false;
        }
''',
    '''        if title_response.clicked() {
            self.show_app_menu = !self.show_app_menu;
            self.show_profile = false;
            self.show_settings = false;
        }
'''
)
text = text.replace(
    '''        if profile_response.clicked() {
            self.draft_name = self.profile_name.clone();
            self.show_profile = true;
            self.show_settings = false;
        }
''',
    '''        if profile_response.clicked() {
            self.draft_name = self.profile_name.clone();
            self.draft_avatar_data = self.profile_avatar_data.clone();
            self.draft_avatar_texture = self.profile_avatar_texture.clone();
            self.show_profile = true;
            self.show_settings = false;
            self.show_app_menu = false;
        }
'''
)

old = '''            if index == 0 {
                painter.circle_filled(center, 24.0, Color32::from_rgb(64, 77, 79));
                paint_initials(painter, center, &self.profile_name, Color32::WHITE);
                if self.local_talking {
'''
new = '''            if index == 0 {
                painter.circle_filled(center, 24.0, Color32::from_rgb(64, 77, 79));
                if let Some(texture) = &self.profile_avatar_texture {
                    let rect = Rect::from_center_size(center, vec2(48.0, 48.0));
                    painter.image(texture.id(), rect, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
                } else {
                    paint_initials(painter, center, &self.profile_name, Color32::WHITE);
                }
                if self.local_talking {
'''
if old not in text:
    raise SystemExit('local avatar block not found')
text = text.replace(old, new)

start = text.index('    fn paint_profile_sheet(&mut self, ui: &mut egui::Ui, canvas: Rect) {')
end = text.index('    fn paint_settings_sheet(&mut self, ui: &mut egui::Ui, canvas: Rect) {', start)
replacement = r'''    fn paint_app_menu(&mut self, ui: &mut egui::Ui, canvas: Rect) {
        let painter = ui.painter();
        let menu = design_rect(canvas, 104.0, 52.0, 176.0, 80.0);
        painter.rect_filled(menu, 10.0, Color32::from_rgba_unmultiplied(250, 250, 250, 250));
        painter.rect_stroke(menu, 10.0, Stroke::new(1.0, Color32::from_gray(205)), egui::StrokeKind::Inside);

        let settings_row = Rect::from_min_size(menu.min + vec2(6.0, 6.0), vec2(164.0, 32.0));
        let settings_response = ui.interact(settings_row, Id::new("app-menu-settings"), Sense::click());
        if settings_response.hovered() {
            painter.rect_filled(settings_row, 7.0, Color32::from_rgb(232, 232, 232));
        }
        painter.text(settings_row.min + vec2(10.0, 16.0), Align2::LEFT_CENTER, "Iroh Settings…", FontId::proportional(13.0), Color32::from_rgb(23, 23, 23));
        if settings_response.clicked() {
            self.show_settings = true;
            self.show_profile = false;
            self.show_app_menu = false;
        }

        let quit_row = Rect::from_min_size(menu.min + vec2(6.0, 42.0), vec2(164.0, 32.0));
        let quit_response = ui.interact(quit_row, Id::new("app-menu-quit"), Sense::click());
        if quit_response.hovered() {
            painter.rect_filled(quit_row, 7.0, Color32::from_rgb(232, 232, 232));
        }
        painter.text(quit_row.min + vec2(10.0, 16.0), Align2::LEFT_CENTER, "Quit Landline", FontId::proportional(13.0), Color32::from_rgb(23, 23, 23));
        if quit_response.clicked() {
            ui.ctx().send_viewport_cmd(ViewportCommand::Close);
        }
    }

    fn paint_profile_sheet(&mut self, ui: &mut egui::Ui, canvas: Rect) {
        let painter = ui.painter();
        painter.rect_filled(canvas, 24.0, Color32::from_rgba_unmultiplied(248, 248, 248, 26));

        let sheet = design_rect(canvas, 0.0, 88.0, 320.0, 584.0);
        painter.rect_filled(sheet, 16.0, Color32::from_rgba_unmultiplied(255, 255, 255, 242));
        painter.text(sheet.min + vec2(24.0, 64.0), Align2::LEFT_BOTTOM, "Edit profile", FontId::proportional(24.0), Color32::from_rgb(23, 23, 23));

        let close_rect = Rect::from_min_size(sheet.min + vec2(280.0, 8.0), vec2(32.0, 32.0));
        let close_response = ui.interact(close_rect, Id::new("profile-close"), Sense::click());
        if close_response.hovered() {
            painter.rect_filled(close_rect, 10.0, Color32::from_rgb(243, 243, 243));
        }
        let cc = close_rect.center();
        painter.line_segment([cc + vec2(-4.0, -4.0), cc + vec2(4.0, 4.0)], Stroke::new(1.8, Color32::from_rgb(23, 23, 23)));
        painter.line_segment([cc + vec2(4.0, -4.0), cc + vec2(-4.0, 4.0)], Stroke::new(1.8, Color32::from_rgb(23, 23, 23)));
        if close_response.clicked() {
            self.show_profile = false;
        }

        painter.text(sheet.min + vec2(24.0, 114.5), Align2::LEFT_CENTER, "Name", FontId::proportional(14.0), Color32::from_rgb(23, 23, 23));
        let name_rect = Rect::from_min_size(sheet.min + vec2(24.0, 128.0), vec2(272.0, 48.0));
        painter.rect_filled(name_rect, 16.0, Color32::from_rgb(243, 243, 243));
        ui.allocate_ui_at_rect(name_rect.shrink2(vec2(16.0, 8.0)), |ui| {
            ui.visuals_mut().override_text_color = Some(Color32::from_rgb(23, 23, 23));
            ui.add_sized([240.0, 32.0], egui::TextEdit::singleline(&mut self.draft_name).font(FontId::proportional(16.0)).frame(false).hint_text("Random Caller"));
        });

        painter.text(sheet.min + vec2(24.0, 218.5), Align2::LEFT_CENTER, "Avatar", FontId::proportional(14.0), Color32::from_rgb(23, 23, 23));
        let avatar_rect = Rect::from_min_size(sheet.min + vec2(24.0, 232.0), vec2(272.0, 208.0));
        painter.rect_filled(avatar_rect, 16.0, Color32::from_rgb(243, 243, 243));
        let avatar_response = ui.interact(avatar_rect, Id::new("profile-avatar-upload"), Sense::click());
        let avatar_image_rect = Rect::from_center_size(avatar_rect.center(), vec2(144.0, 144.0));
        if let Some(texture) = &self.draft_avatar_texture {
            painter.image(texture.id(), avatar_image_rect, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
        } else {
            painter.circle_filled(avatar_image_rect.center(), 72.0, Color32::from_rgba_unmultiplied(23, 23, 23, 18));
            let upload = Rect::from_center_size(avatar_image_rect.center(), vec2(24.0, 24.0));
            painter.rect_stroke(upload.shrink(3.0), 1.0, Stroke::new(1.0, Color32::from_gray(180)), egui::StrokeKind::Inside);
            painter.line_segment([upload.center() + vec2(0.0, 4.0), upload.center() + vec2(0.0, -5.0)], Stroke::new(1.2, Color32::from_rgb(70, 70, 70)));
            painter.line_segment([upload.center() + vec2(-3.0, -2.0), upload.center() + vec2(0.0, -5.0)], Stroke::new(1.2, Color32::from_rgb(70, 70, 70)));
            painter.line_segment([upload.center() + vec2(3.0, -2.0), upload.center() + vec2(0.0, -5.0)], Stroke::new(1.2, Color32::from_rgb(70, 70, 70)));
        }

        if avatar_response.clicked() {
            if let Some(path) = rfd::FileDialog::new().add_filter("Image", &["png", "jpg", "jpeg"]).pick_file() {
                self.load_avatar_path(ui.ctx(), &path);
            }
        }

        painter.text(sheet.min + vec2(160.0, 476.0), Align2::CENTER_CENTER, "Click to upload or drop an image to customise", FontId::proportional(12.0), Color32::from_rgb(107, 107, 107));
        let changed = normalize_name(&self.draft_name) != self.profile_name || self.draft_avatar_data != self.profile_avatar_data;
        let button_rect = Rect::from_min_size(sheet.min + vec2(24.0, 512.0), vec2(272.0, 48.0));
        let button_fill = if changed { Color32::from_rgb(23, 23, 23) } else { Color32::from_rgba_unmultiplied(23, 23, 23, 51) };
        let button_text = if changed { Color32::from_rgb(235, 235, 235) } else { Color32::from_rgb(107, 107, 107) };
        painter.rect_filled(button_rect, 16.0, button_fill);
        painter.text(button_rect.center(), Align2::CENTER_CENTER, "Update", FontId::proportional(14.0), button_text);
        if changed && ui.interact(button_rect, Id::new("profile-update"), Sense::click()).clicked() {
            self.save_profile();
        }
    }

'''
text = text[:start] + replacement + text[end:]

text = text.replace(
    'ui.small("Click and drag the LANDLINE wordmark to move the window. Click it without dragging to open or close this panel.");',
    'ui.small("Open this panel from LANDLINE > Iroh Settings. Drag the LANDLINE wordmark to move the window.");'
)

text = text.replace(
    '''        self.poll_network();
        self.pump_audio();
        ctx.request_repaint_after(Duration::from_millis(33));
''',
    '''        self.poll_network();
        self.pump_audio();
        if self.show_profile {
            let dropped = ctx.input(|input| input.raw.dropped_files.clone());
            if let Some(path) = dropped.iter().filter_map(|file| file.path.as_deref()).next() {
                self.load_avatar_path(ctx, path);
            }
        }
        ctx.request_repaint_after(Duration::from_millis(33));
'''
)
text = text.replace(
    '''            self.paint_volume(ui, canvas);
            self.paint_vu(ui, canvas);

            if self.show_profile {
''',
    '''            self.paint_volume(ui, canvas);
            self.paint_vu(ui, canvas);

            if self.show_app_menu && !self.show_profile && !self.show_settings {
                self.paint_app_menu(ui, canvas);
            }

            if self.show_profile {
'''
)

helper_start = text.index('fn load_profile_name() -> String {')
text = text[:helper_start] + r'''fn load_profile() -> StoredProfile {
    let fallback = StoredProfile { name: "Caller".into(), avatar_data: None };
    let Some(path) = profile_path() else { return fallback; };
    fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<StoredProfile>(&bytes).ok())
        .map(|mut profile| {
            profile.name = normalize_name(&profile.name);
            profile
        })
        .unwrap_or(fallback)
}

fn save_stored_profile(profile: &StoredProfile) -> anyhow::Result<()> {
    let path = profile_path().ok_or_else(|| anyhow::anyhow!("configuration directory unavailable"))?;
    if let Some(parent) = path.parent() { fs::create_dir_all(parent)?; }
    fs::write(path, serde_json::to_vec_pretty(profile)?)?;
    Ok(())
}

fn texture_from_avatar_data(ctx: &egui::Context, name: &str, encoded: &str) -> Option<TextureHandle> {
    let bytes = BASE64.decode(encoded).ok()?;
    let (_, image) = prepare_avatar(&bytes).ok()?;
    Some(ctx.load_texture(name, image, TextureOptions::LINEAR))
}

fn prepare_avatar(bytes: &[u8]) -> anyhow::Result<(String, ColorImage)> {
    let decoded = image::load_from_memory(bytes)?;
    let rgba = decoded.to_rgba8();
    let side = rgba.width().min(rgba.height());
    let x = (rgba.width() - side) / 2;
    let y = (rgba.height() - side) / 2;
    let cropped = image::imageops::crop_imm(&rgba, x, y, side, side).to_image();
    let resized = image::imageops::resize(&cropped, 144, 144, FilterType::Lanczos3);

    let rgb = image::DynamicImage::ImageRgba8(resized.clone()).to_rgb8();
    let mut jpeg = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut jpeg, 82)
        .encode_image(&image::DynamicImage::ImageRgb8(rgb))?;

    let mut circular = resized;
    let radius = 72.0_f32;
    let centre = 71.5_f32;
    for yy in 0..144_u32 {
        for xx in 0..144_u32 {
            let dx = xx as f32 - centre;
            let dy = yy as f32 - centre;
            if dx * dx + dy * dy > radius * radius {
                circular.get_pixel_mut(xx, yy).0[3] = 0;
            }
        }
    }
    let image = ColorImage::from_rgba_unmultiplied([144, 144], circular.as_raw());
    Ok((BASE64.encode(jpeg), image))
}
'''
ui.write_text(text)
