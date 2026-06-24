#!/usr/bin/env python3
"""Compose une icône pleine 1024x1024 (sans alpha) depuis le logo arrondi transparent."""
import os, subprocess, base64

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = "/Users/adelhanifi/Downloads/adhanbox-logo.png"
OUT_DIR = os.path.join(ROOT, "flutter_app/assets/images")
os.makedirs(OUT_DIR, exist_ok=True)

b64 = base64.b64encode(open(SRC, "rb").read()).decode()
data = f"data:image/png;base64,{b64}"

# Fond plein : dégradé vert proche du logo, + copie floutée agrandie pour remplir les coins
html = f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{margin:0;padding:0;box-sizing:border-box;}}
html,body{{width:1024px;height:1024px;overflow:hidden;}}
.wrap{{position:relative;width:1024px;height:1024px;
  background:linear-gradient(160deg,#1f7a5a 0%,#125c41 45%,#08381f 100%);}}
.bg{{position:absolute;inset:-80px;background:url('{data}') center/cover no-repeat;
  filter:blur(40px);transform:scale(1.25);}}
.fg{{position:absolute;inset:0;background:url('{data}') center/122% no-repeat;}}
</style></head><body>
<div class="wrap"><div class="bg"></div><div class="fg"></div></div>
</body></html>"""

hp = os.path.join(os.path.dirname(__file__), "_icon.html")
open(hp, "w").write(html)
out = os.path.join(OUT_DIR, "app_logo.png")
chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
subprocess.run([chrome,"--headless","--disable-gpu","--hide-scrollbars",
  "--force-device-scale-factor=1","--window-size=1024,1024",
  f"--screenshot={out}",f"file://{hp}"],check=True,capture_output=True)
# Chrome produit un PNG avec alpha; on l'aplatit via sips (JPEG->PNG enlève l'alpha)
tmp = "/tmp/_flat.jpg"
subprocess.run(["sips","-s","format","jpeg",out,"--out",tmp],check=True,capture_output=True)
subprocess.run(["sips","-s","format","png",tmp,"--out",out],check=True,capture_output=True)
print("OK", out)
