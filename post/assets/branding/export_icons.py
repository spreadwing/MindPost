import os
import subprocess
from PIL import Image

EDGE_PATH = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BRANDING_DIR = os.path.dirname(os.path.abspath(__file__))

ref_candidates = [
    "candidate_ref_1_exact_palette",
    "candidate_ref_2_cyan_bg",
    "candidate_ref_3_capsule_airplane",
    "candidate_ref_4_navy_bg"
]

for name in ref_candidates:
    svg_path = os.path.join(BRANDING_DIR, f"{name}.svg")
    if not os.path.exists(svg_path):
        continue
    html_temp = os.path.join(BRANDING_DIR, f"temp_{name}.html")
    png_path = os.path.join(BRANDING_DIR, f"{name}.png")
    ico_path = os.path.join(BRANDING_DIR, f"{name}.ico")
    
    html_content = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  html, body {{
    margin: 0;
    padding: 0;
    width: 512px;
    height: 512px;
    overflow: hidden;
    background: transparent;
  }}
  img {{
    width: 512px;
    height: 512px;
    display: block;
  }}
</style>
</head>
<body>
  <img src="{name}.svg">
</body>
</html>"""
    with open(html_temp, "w", encoding="utf-8") as f:
        f.write(html_content)
        
    cmd = [
        EDGE_PATH,
        "--headless",
        "--disable-gpu",
        "--hide-scrollbars",
        "--default-background-color=00000000",
        f"--window-size=512,512",
        f"--screenshot={png_path}",
        html_temp
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    if os.path.exists(html_temp):
        os.remove(html_temp)
        
    if os.path.exists(png_path):
        img = Image.open(png_path).convert("RGBA")
        img.save(ico_path, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
        print(f"Exported: {name}.png and {name}.ico")

print("All reference-matching candidates exported successfully!")
