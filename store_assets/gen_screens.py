#!/usr/bin/env python3
"""Génère 5 aperçus App Store (1242x2688) pour AdhanBox via Chrome headless."""
import os, subprocess

OUT = os.path.join(os.path.dirname(__file__), "screenshots")
os.makedirs(OUT, exist_ok=True)

# Palette fidèle à l'app
EMERALD = "#10b981"
EMERALD_DEEP = "#0b6b4f"
BG = "#0a1422"
CARD = "#141f2e"
BORDER = "#22303f"
TEXT = "#e9eef3"
MUTED = "#8b9bab"

FONT = ("-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', "
        "Roboto, Helvetica, Arial, sans-serif")

def page(caption_top, caption_accent, subtitle, screen_html):
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{margin:0;padding:0;box-sizing:border-box;font-family:{FONT};-webkit-font-smoothing:antialiased;}}
html,body{{width:1242px;height:2688px;overflow:hidden;}}
body{{background:linear-gradient(165deg,{EMERALD_DEEP} 0%,#08533d 18%,{BG} 46%);}}
.cap{{padding:150px 96px 0;text-align:center;}}
.cap h1{{font-size:86px;line-height:1.08;font-weight:800;color:#fff;letter-spacing:-1.5px;}}
.cap h1 .ac{{color:#9ff5d4;}}
.cap p{{margin-top:34px;font-size:40px;color:#d6f5e9;font-weight:500;line-height:1.3;}}
/* Cadre téléphone */
.phone{{position:absolute;left:50%;transform:translateX(-50%);top:760px;width:980px;height:1850px;
  background:{BG};border-radius:78px;border:16px solid #1c2735;
  box-shadow:0 50px 120px rgba(0,0,0,.55), 0 0 0 6px rgba(255,255,255,.04);overflow:hidden;}}
.notch{{position:absolute;top:0;left:50%;transform:translateX(-50%);width:300px;height:42px;
  background:#1c2735;border-radius:0 0 28px 28px;z-index:5;}}
.scr{{position:absolute;inset:0;background:{BG};color:{TEXT};display:flex;flex-direction:column;}}
.hdr{{background:{EMERALD_DEEP};padding:64px 44px 30px;display:flex;align-items:center;gap:26px;}}
.hdr .bk{{font-size:46px;color:#fff;opacity:.9;}}
.hdr h2{{font-size:48px;color:#fff;font-weight:700;}}
.body{{padding:40px 44px;display:flex;flex-direction:column;gap:30px;overflow:hidden;}}
/* Carte prière */
.card{{background:{CARD};border:2px solid {BORDER};border-radius:34px;padding:34px;}}
.crow{{display:flex;align-items:center;gap:26px;}}
.ic{{width:88px;height:88px;border-radius:24px;display:flex;align-items:center;justify-content:center;font-size:44px;}}
.nm{{font-size:46px;font-weight:600;flex:1;}}
.play{{width:74px;height:74px;border-radius:50%;background:{EMERALD};display:flex;align-items:center;justify-content:center;font-size:36px;color:#04130d;}}
.sw{{width:118px;height:66px;border-radius:33px;background:{EMERALD};position:relative;}}
.sw::after{{content:"";position:absolute;top:6px;right:6px;width:54px;height:54px;border-radius:50%;background:#fff;}}
.sep{{height:2px;background:{BORDER};margin:30px -34px;}}
.lbl{{font-size:32px;color:{MUTED};margin-bottom:16px;}}
.drop{{background:{BG};border:2px solid {BORDER};border-radius:22px;padding:30px 32px;font-size:42px;display:flex;justify-content:space-between;align-items:center;}}
.chk{{display:flex;align-items:center;gap:24px;font-size:38px;color:{TEXT};margin-top:30px;}}
.cbox{{width:56px;height:56px;border-radius:14px;background:{EMERALD};display:flex;align-items:center;justify-content:center;color:#fff;font-size:36px;}}
.vrow{{display:flex;align-items:center;gap:26px;margin-top:30px;}}
.track{{flex:1;height:14px;border-radius:7px;background:linear-gradient(90deg,{EMERALD} 60%,{BORDER} 60%);position:relative;}}
.knob{{position:absolute;top:50%;left:60%;transform:translate(-50%,-50%);width:54px;height:54px;border-radius:50%;background:{EMERALD};box-shadow:0 0 0 10px rgba(16,185,129,.18);}}
.vval{{font-size:34px;font-weight:700;color:{EMERALD};}}
.muted{{color:{MUTED};}}
/* liste horaires */
.ptime{{display:flex;justify-content:space-between;align-items:center;padding:36px 4px;border-bottom:2px solid {BORDER};}}
.ptime .l{{display:flex;align-items:center;gap:26px;font-size:46px;}}
.ptime .t{{font-size:50px;font-weight:700;}}
.ptime.active .t{{color:{EMERALD};}}
.next{{background:linear-gradient(135deg,{EMERALD_DEEP},#0a4a37);border-radius:34px;padding:46px;text-align:center;margin-bottom:8px;}}
.next .k{{font-size:34px;color:#bdf0dd;letter-spacing:2px;}}
.next .big{{font-size:96px;font-weight:800;color:#fff;margin-top:10px;}}
.next .s{{font-size:38px;color:#d6f5e9;margin-top:6px;}}
/* LEDs */
.ledgrid{{display:flex;flex-wrap:wrap;gap:24px;justify-content:center;padding:14px 0;}}
.led{{width:120px;height:120px;border-radius:50%;}}
.tile{{background:{CARD};border:2px solid {BORDER};border-radius:28px;padding:34px;display:flex;align-items:center;gap:26px;font-size:40px;}}
.dot{{width:60px;height:60px;border-radius:50%;}}
/* setup */
.step{{display:flex;align-items:center;gap:30px;background:{CARD};border:2px solid {BORDER};border-radius:30px;padding:38px;}}
.num{{width:84px;height:84px;border-radius:50%;background:{EMERALD};color:#04130d;font-size:44px;font-weight:800;display:flex;align-items:center;justify-content:center;}}
.step .st{{font-size:42px;font-weight:600;}}
.step .sd{{font-size:32px;color:{MUTED};margin-top:8px;}}
.bigbtn{{margin-top:14px;background:{EMERALD};color:#04130d;font-size:46px;font-weight:700;text-align:center;padding:42px;border-radius:30px;}}
</style></head><body>
<div class="cap"><h1>{caption_top} <span class="ac">{caption_accent}</span></h1><p>{subtitle}</p></div>
<div class="phone"><div class="notch"></div><div class="scr">{screen_html}</div></div>
</body></html>"""

def prayer_card(icon, icon_bg, icon_col, name, on=True):
    sw = f'<div class="sw"></div>' if on else ''
    return f"""<div class="card"><div class="crow">
      <div class="ic" style="background:{icon_bg};color:{icon_col}">{icon}</div>
      <div class="nm">{name}</div><div class="play">▶</div>{sw}</div>
      <div class="sep"></div>
      <div class="lbl">Adhan</div>
      <div class="drop">Adhan 1 <span class="muted">▾</span></div>
      <div class="chk"><div class="cbox">✓</div> Jouer la Doua après l'adhan</div>
    </div>"""

# --- Écran 1 : Config adhan ---
s1 = f"""<div class="hdr"><span class="bk">‹</span><h2>Appel à la prière</h2></div>
<div class="body">
{prayer_card('🌅','#3b3a6b','#c7c6ff','Fajr')}
{prayer_card('☀️','#6b5a1f','#ffe08a','Dhuhr')}
</div>"""

# --- Écran 2 : Horaires ---
def pt(icon,name,time,active=False):
    cls = " active" if active else ""
    return f'<div class="ptime{cls}"><div class="l">{icon} {name}</div><div class="t">{time}</div></div>'
s2 = f"""<div class="hdr"><span class="bk">‹</span><h2>Horaires de prière</h2></div>
<div class="body">
  <div class="next"><div class="k">PROCHAINE PRIÈRE · ASR</div><div class="big">15:42</div><div class="s">dans 2 h 18 min</div></div>
  {pt('🌅','Fajr','06:14')}
  {pt('🌄','Shourouq','07:51')}
  {pt('☀️','Dhuhr','13:28')}
  {pt('🌤️','Asr','15:42', True)}
  {pt('🌇','Maghrib','18:55')}
  {pt('🌙','Isha','20:31')}
</div>"""

# --- Écran 3 : Volume ---
s3 = f"""<div class="hdr"><span class="bk">‹</span><h2>Appel à la prière</h2></div>
<div class="body">
  <div class="card"><div class="crow"><div class="ic" style="background:#134e3a;color:{EMERALD}">🔊</div>
    <div class="nm">Volume général</div><div class="vval">22 / 30</div></div>
    <div class="vrow"><span class="muted" style="font-size:40px">🔈</span><div class="track"><div class="knob"></div></div><span style="font-size:40px;color:{EMERALD}">🔊</span></div>
  </div>
  {prayer_card('🌅','#3b3a6b','#c7c6ff','Fajr')}
</div>"""

# --- Écran 4 : Configuration ---
s4 = f"""<div class="hdr"><span class="bk">‹</span><h2>Configurer l'appareil</h2></div>
<div class="body">
  <div class="step"><div class="num">1</div><div><div class="st">Allumez votre AdhanBox</div><div class="sd">Le boîtier passe en mode appairage</div></div></div>
  <div class="step"><div class="num">2</div><div><div class="st">Connexion Bluetooth</div><div class="sd">L'app détecte l'appareil automatiquement</div></div></div>
  <div class="step"><div class="num">3</div><div><div class="st">Choisissez votre Wi-Fi</div><div class="sd">Saisissez le mot de passe, c'est prêt</div></div></div>
  <div class="bigbtn">🔗  Rechercher mon AdhanBox</div>
</div>"""

# --- Écran 5 : LEDs ---
leds = ['#10b981','#22c55e','#06b6d4','#3b82f6','#8b5cf6','#ec4899','#f59e0b','#ef4444']
ledhtml = "".join(f'<div class="led" style="background:{c};box-shadow:0 0 40px {c}88"></div>' for c in leds)
s5 = f"""<div class="hdr"><span class="bk">‹</span><h2>Ambiance lumineuse</h2></div>
<div class="body">
  <div class="card"><div class="lbl" style="font-size:38px;margin-bottom:30px">16 LEDs de notification</div>
    <div class="ledgrid">{ledhtml}</div></div>
  <div class="tile"><div class="dot" style="background:{EMERALD};box-shadow:0 0 30px {EMERALD}"></div> Mode Prière</div>
  <div class="tile"><div class="dot" style="background:#3b82f6;box-shadow:0 0 30px #3b82f6"></div> Veille douce</div>
  <div class="tile"><div class="dot" style="background:#f59e0b;box-shadow:0 0 30px #f59e0b"></div> Coucher de soleil</div>
</div>"""

screens = [
    ("01_adhan", "Un adhan", "pour chaque prière", "Choisissez l'appel joué à Fajr, Dhuhr, Asr, Maghrib et Isha.", s1),
    ("02_horaires", "Ne manquez", "plus une prière", "Horaires calculés précisément pour votre localité.", s2),
    ("03_volume", "Réglez le volume", "en direct", "Volume général ou par prière, avec écoute immédiate.", s3),
    ("04_setup", "Installé", "en 2 minutes", "Connexion Bluetooth guidée, sans compte ni configuration complexe.", s4),
    ("05_leds", "Pilotez", "l'ambiance", "16 LEDs personnalisables pour accompagner chaque moment.", s5),
]

chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for name, top, accent, sub, scr in screens:
    html = page(top, accent, sub, scr)
    hp = os.path.join(OUT, f"{name}.html")
    open(hp, "w").write(html)
    png = os.path.join(OUT, f"{name}.png")
    subprocess.run([chrome, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", "--window-size=1242,2688",
                    f"--screenshot={png}", f"file://{hp}"],
                   check=True, capture_output=True)
    print("OK", png)
print("Terminé.")
