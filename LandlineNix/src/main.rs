mod audio;
mod network;
mod ui;
mod wire;

use eframe::egui;

fn main() -> eframe::Result {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Landline")
            .with_decorations(false)
            .with_inner_size([320.0, 672.0])
            .with_min_inner_size([320.0, 672.0])
            .with_transparent(true),
        ..Default::default()
    };

    eframe::run_native(
        "Landline",
        options,
        Box::new(|cc| Ok(Box::new(ui::LandlineApp::new(cc)))),
    )
}
