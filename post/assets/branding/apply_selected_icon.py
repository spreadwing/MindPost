import os
import subprocess
from PIL import Image

EDGE_PATH = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BRANDING_DIR = r"e:\API\post\assets\branding"
svg_path = os.path.join(BRANDING_DIR, "candidate_ref_4_navy_bg.svg")
temp_html = os.path.join(BRANDING_DIR, "temp_1024.html")
png_1024 = os.path.join(BRANDING_DIR, "app_icon_1024.png")

html = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body {
    margin: 0;
    padding: 0;
    width: 1024px;
    height: 1024px;
    overflow: hidden;
    background: transparent;
  }
  img {
    width: 1024px;
    height: 1024px;
    display: block;
  }
</style>
</head>
<body>
  <img src="candidate_ref_4_navy_bg.svg">
</body>
</html>"""

with open(temp_html, "w", encoding="utf-8") as f:
    f.write(html)

subprocess.run([
    EDGE_PATH,
    "--headless",
    "--disable-gpu",
    "--hide-scrollbars",
    "--default-background-color=00000000",
    "--window-size=1024,1024",
    f"--screenshot={png_1024}",
    temp_html
], check=True)

if os.path.exists(temp_html):
    os.remove(temp_html)

# 1. Update macOS appiconset
macos_dir = r"e:\API\post\macos\Runner\Assets.xcassets\AppIcon.appiconset"
sizes = [16, 32, 64, 128, 256, 512, 1024]
base_img = Image.open(png_1024).convert("RGBA")

for s in sizes:
    resized = base_img.resize((s, s), Image.Resampling.LANCZOS)
    target = os.path.join(macos_dir, f"app_icon_{s}.png")
    resized.save(target)
    print(f"Saved macOS icon: app_icon_{s}.png")

# 2. Save a canonical app_logo.png in assets
resized_256 = base_img.resize((256, 256), Image.Resampling.LANCZOS)
resized_256.save(r"e:\API\post\assets\app_logo.png")
print("Saved assets/app_logo.png")

# 3. Ensure windows/runner/resources/app_icon.ico is up to date
ico_path = os.path.join(BRANDING_DIR, "candidate_ref_4_navy_bg.ico")
windows_ico = r"e:\API\post\windows\runner\resources\app_icon.ico"
if os.path.exists(ico_path):
    with open(ico_path, "rb") as src, open(windows_ico, "wb") as dst:
        dst.write(src.read())
    print("Updated windows/runner/resources/app_icon.ico")

print("All platform icon assets updated successfully!")
