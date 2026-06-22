#!/usr/bin/env python3
"""Génère le graphique de présentation Google Play (1024x500)."""
import os, subprocess, base64

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(os.path.dirname(__file__), "google_play")
os.makedirs(OUT, exist_ok=True)

logo = os.path.join(ROOT, "flutter_app/assets/images/app_logo.png")
b64 = base64.b64encode(open(logo, "rb").read()).decode()

EMERALD="#10b981"; EMERALD_DEEP="#0b6b4f"; BG="#0a1422"
FONT="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Roboto, Arial, sans-serif"

html = f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{margin:0;padding:0;box-sizing:border-box;font-family:{FONT};-webkit-font-smoothing:antialiased;}}
html,body{{width:1024px;height:500px;overflow:hidden;}}
body{{background:radial-gradient(1200px 600px at 78% 30%, {EMERALD_DEEP} 0%, #08533d 30%, {BG} 70%);
  display:flex;align-items:center;gap:60px;padding:0 90px;}}
.logo{{width:280px;height:280px;border-radius:64px;box-shadow:0 30px 70px rgba(0,0,0,.5);flex-shrink:0;}}
.txt h1{{font-size:104px;font-weight:800;color:#fff;letter-spacing:-2px;line-height:1;}}
.txt h1 .b{{color:#9ff5d4;}}
.txt p{{margin-top:26px;font-size:42px;color:#d6f5e9;font-weight:500;line-height:1.25;}}
.glow{{position:absolute;}}
</style></head><body>
<img class="logo" src="data:image/png;base64,{b64}">
<div class="txt"><h1>Adhan<span class="b">Box</span></h1>
<p>L'appel à la prière connecté,<br>à l'heure exacte, chez vous.</p></div>
</body></html>"""

hp = os.path.join(OUT, "feature.html"); open(hp, "w").write(html)
png = os.path.join(OUT, "feature_graphic_1024x500.png")
chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
subprocess.run([chrome,"--headless","--disable-gpu","--hide-scrollbars",
  "--force-device-scale-factor=1","--window-size=1024,500",
  f"--screenshot={png}",f"file://{hp}"],check=True,capture_output=True)
print("OK", png)
