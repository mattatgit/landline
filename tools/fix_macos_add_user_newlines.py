from pathlib import Path

path = Path("LandlineMac/ContentView.swift")
text = path.read_text()
start_marker = r"\n\nprivate struct EmptyAddSlot: View {"
end_marker = "\n\nprivate struct RadioDisplay: View {"

start = text.find(start_marker)
if start < 0:
    raise SystemExit("Could not find generated Add User block start")
end = text.find(end_marker, start)
if end < 0:
    raise SystemExit("Could not find Add User block end")

block = text[start:end]
block = block.replace(r"\n", "\n")
text = text[:start] + block + text[end:]
path.write_text(text)
print("Normalized generated Add User newlines")
