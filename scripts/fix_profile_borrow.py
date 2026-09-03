from pathlib import Path

path = Path("LandlineNix/src/ui.rs")
text = path.read_text()

start = text.index("    fn paint_profile_sheet(")
end = text.index("    fn paint_settings_sheet(", start)
block = text[start:end]
block = block.replace("        let painter = ui.painter();\n", "", 1)
block = block.replace("painter.", "ui.painter().")
text = text[:start] + block + text[end:]

# The title bar now renders image widgets directly, so this old painter binding
# is no longer needed and only produces a compiler warning.
top_start = text.index("    fn paint_top_bar(")
top_end = text.index("    fn paint_radio(", top_start)
top = text[top_start:top_end]
top = top.replace("        let painter = ui.painter();\n", "", 1)
text = text[:top_start] + top + text[top_end:]

path.write_text(text)
