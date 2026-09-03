use std::{env, fs, path::{Path, PathBuf}};

fn main() {
    println!("cargo:rerun-if-env-changed=LANDLINE_FONT_DIR");

    let font_root = env::var("LANDLINE_FONT_DIR")
        .map(PathBuf::from)
        .expect("LANDLINE_FONT_DIR must be provided by the Nix development shell");

    let mut files = Vec::new();
    collect_fonts(&font_root, &mut files);

    let inter_tight = choose_font(&files, "intertight")
        .expect("Inter Tight font was not found in LANDLINE_FONT_DIR");
    let inter = choose_font_excluding(&files, "inter", "intertight")
        .expect("Inter font was not found in LANDLINE_FONT_DIR");

    let out = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR missing"));
    fs::copy(inter_tight, out.join("InterTight.ttf")).expect("copy Inter Tight font");
    fs::copy(inter, out.join("Inter.ttf")).expect("copy Inter font");
}

fn collect_fonts(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else { return; };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_fonts(&path, out);
        } else if matches!(path.extension().and_then(|ext| ext.to_str()).map(|ext| ext.to_ascii_lowercase()).as_deref(), Some("ttf" | "otf")) {
            out.push(path);
        }
    }
}

fn normalized_name(path: &Path) -> String {
    path.file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric())
        .collect()
}

fn score(path: &Path) -> i32 {
    let name = normalized_name(path);
    let mut value = 0;
    if name.contains("variable") || name.contains("wght") { value += 4; }
    if !name.contains("italic") && !name.contains("slnt") { value += 6; }
    if name.ends_with("ttf") { value += 1; }
    value
}

fn choose_font(files: &[PathBuf], needle: &str) -> Option<PathBuf> {
    files.iter()
        .filter(|path| normalized_name(path).contains(needle))
        .max_by_key(|path| score(path))
        .cloned()
}

fn choose_font_excluding(files: &[PathBuf], needle: &str, excluded: &str) -> Option<PathBuf> {
    files.iter()
        .filter(|path| {
            let name = normalized_name(path);
            name.contains(needle) && !name.contains(excluded)
        })
        .max_by_key(|path| score(path))
        .cloned()
}
