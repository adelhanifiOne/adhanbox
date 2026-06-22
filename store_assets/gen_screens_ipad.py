#!/usr/bin/env python3
"""Génère des aperçus iPad 13\" (2048x2732) pour AdhanBox via Chrome headless."""
import os, subprocess

OUT = os.path.join(os.path.dirname(__file__), "screenshots_ipad")
os.makedirs(OUT, exist_ok=True)

EMERALD="#10b981"; EMERALD_DEEP="#0b6b4f"; BG="#0a1422"; CARD="#141f2e"
BORDER="#22303f"; TEXT="#e9eef3"; MUTED="#8b9bab"
FONT=("-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif")

def page(top, accent, sub, screen):
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
*{{margin:0;padding:0;box-sizing:border-box;font-family:{FONT};-webkit-font-smoothing:antialiased;}}
html,body{{width:2048px;height:2732px;overflow:hidden;}}
body{{background:linear-gradient(165deg,{EMERALD_DEEP} 0%,#08533d 16%,{BG} 44%);}}
.cap{{padding:170px 160px 0;text-align:center;}}
.cap h1{{font-size:120px;line-height:1.06;font-weight:800;color:#fff;letter-spacing:-2px;}}
.cap h1 .ac{{color:#9ff5d4;}}
.cap p{{margin-top:42px;font-size:54px;color:#d6f5e9;font-weight:500;}}
.tablet{{position:absolute;left:50%;transform:translateX(-50%);top:820px;width:1500px;height:1820px;
  background:{BG};border-radius:64px;border:20px solid #1c2735;
  box-shadow:0 60px 140px rgba(0,0,0,.55),0 0 0 8px rgba(255,255,255,.04);overflow:hidden;}}
.scr{{position:absolute;inset:0;background:{BG};color:{TEXT};display:flex;flex-direction:column;}}
.hdr{{background:{EMERALD_DEEP};padding:60px 64px 44px;display:flex;align-items:center;gap:30px;}}
.hdr .bk{{font-size:54px;color:#fff;opacity:.9;}} .hdr h2{{font-size:60px;color:#fff;font-weight:700;}}
.body{{padding:56px 90px;display:flex;flex-direction:column;gap:38px;}}
.card{{background:{CARD};border:2px solid {BORDER};border-radius:40px;padding:46px;}}
.crow{{display:flex;align-items:center;gap:34px;}}
.ic{{width:108px;height:108px;border-radius:30px;display:flex;align-items:center;justify-content:center;font-size:56px;}}
.nm{{font-size:60px;font-weight:600;flex:1;}}
.play{{width:92px;height:92px;border-radius:50%;background:{EMERALD};display:flex;align-items:center;justify-content:center;font-size:46px;color:#04130d;}}
.sw{{width:148px;height:84px;border-radius:42px;background:{EMERALD};position:relative;}}
.sw::after{{content:"";position:absolute;top:8px;right:8px;width:68px;height:68px;border-radius:50%;background:#fff;}}
.sep{{height:2px;background:{BORDER};margin:40px -46px;}}
.lbl{{font-size:40px;color:{MUTED};margin-bottom:20px;}}
.drop{{background:{BG};border:2px solid {BORDER};border-radius:28px;padding:38px 40px;font-size:54px;display:flex;justify-content:space-between;align-items:center;}}
.chk{{display:flex;align-items:center;gap:30px;font-size:48px;margin-top:38px;}}
.cbox{{width:70px;height:70px;border-radius:18px;background:{EMERALD};display:flex;align-items:center;justify-content:center;color:#fff;font-size:44px;}}
.vrow{{display:flex;align-items:center;gap:34px;margin-top:38px;}}
.track{{flex:1;height:18px;border-radius:9px;background:linear-gradient(90deg,{EMERALD} 60%,{BORDER} 60%);position:relative;}}
.knob{{position:absolute;top:50%;left:60%;transform:translate(-50%,-50%);width:68px;height:68px;border-radius:50%;background:{EMERALD};box-shadow:0 0 0 14px rgba(16,185,129,.18);}}
.vval{{font-size:44px;font-weight:700;color:{EMERALD};}}
.muted{{color:{MUTED};}}
.ptime{{display:flex;justify-content:space-between;align-items:center;padding:46px 8px;border-bottom:2px solid {BORDER};}}
.ptime .l{{display:flex;align-items:center;gap:32px;font-size:58px;}} .ptime .t{{font-size:62px;font-weight:700;}}
.ptime.active .t{{color:{EMERALD};}}
.next{{background:linear-gradient(135deg,{EMERALD_DEEP},#0a4a37);border-radius:40px;padding:60px;text-align:center;}}
.next .k{{font-size:42px;color:#bdf0dd;letter-spacing:3px;}} .next .big{{font-size:128px;font-weight:800;color:#fff;margin-top:14px;}}
.next .s{{font-size:48px;color:#d6f5e9;margin-top:10px;}}
.step{{display:flex;align-items:center;gap:38px;background:{CARD};border:2px solid {BORDER};border-radius:36px;padding:48px;}}
.num{{width:104px;height:104px;border-radius:50%;background:{EMERALD};color:#04130d;font-size:56px;font-weight:800;display:flex;align-items:center;justify-content:center;}}
.step .st{{font-size:54px;font-weight:600;}} .step .sd{{font-size:40px;color:{MUTED};margin-top:10px;}}
.bigbtn{{margin-top:16px;background:{EMERALD};color:#04130d;font-size:58px;font-weight:700;text-align:center;padding:54px;border-radius:36px;}}
</style></head><body>
<div class="cap"><h1>{top} <span class="ac">{accent}</span></h1><p>{sub}</p></div>
<div class="tablet"><div class="scr">{screen}</div></div></body></html>"""

def prayer_card(icon, bg, col, name):
    return f"""<div class="card"><div class="crow">
      <div class="ic" style="background:{bg};color:{col}">{icon}</div>
      <div class="nm">{name}</div><div class="play">▶</div><div class="sw"></div></div>
      <div class="sep"></div><div class="lbl">Adhan</div>
      <div class="drop">Adhan 1 <span class="muted">▾</span></div>
      <div class="chk"><div class="cbox">✓</div> Jouer la Doua après l'adhan</div></div>"""

s1=f"""<div class="hdr"><span class="bk">‹</span><h2>Appel à la prière</h2></div>
<div class="body">{prayer_card('🌅','#3b3a6b','#c7c6ff','Fajr')}{prayer_card('☀️','#6b5a1f','#ffe08a','Dhuhr')}</div>"""

def pt(i,n,t,a=False):
    return f'<div class="ptime{" active" if a else ""}"><div class="l">{i} {n}</div><div class="t">{t}</div></div>'
s2=f"""<div class="hdr"><span class="bk">‹</span><h2>Horaires de prière</h2></div>
<div class="body"><div class="next"><div class="k">PROCHAINE PRIÈRE · ASR</div><div class="big">15:42</div><div class="s">dans 2 h 18 min</div></div>
{pt('🌅','Fajr','06:14')}{pt('☀️','Dhuhr','13:28')}{pt('🌤️','Asr','15:42',True)}{pt('🌇','Maghrib','18:55')}{pt('🌙','Isha','20:31')}</div>"""

s4=f"""<div class="hdr"><span class="bk">‹</span><h2>Configurer l'appareil</h2></div>
<div class="body">
<div class="step"><div class="num">1</div><div><div class="st">Allumez votre AdhanBox</div><div class="sd">Le boîtier passe en mode appairage</div></div></div>
<div class="step"><div class="num">2</div><div><div class="st">Connexion Bluetooth</div><div class="sd">L'app détecte l'appareil automatiquement</div></div></div>
<div class="step"><div class="num">3</div><div><div class="st">Choisissez votre Wi-Fi</div><div class="sd">Saisissez le mot de passe, c'est prêt</div></div></div>
<div class="bigbtn">🔗  Rechercher mon AdhanBox</div></div>"""

screens=[
 ("01_adhan","Un adhan","pour chaque prière","Choisissez l'appel joué à chaque prière de la journée.",s1),
 ("02_horaires","Ne manquez","plus une prière","Horaires calculés précisément pour votre localité.",s2),
 ("03_setup","Installé","en 2 minutes","Connexion Bluetooth guidée, sans compte.",s4),
]
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for name,top,acc,sub,scr in screens:
    hp=os.path.join(OUT,f"{name}.html"); open(hp,"w").write(page(top,acc,sub,scr))
    png=os.path.join(OUT,f"{name}.png")
    subprocess.run([chrome,"--headless","--disable-gpu","--hide-scrollbars",
      "--force-device-scale-factor=1","--window-size=2048,2732",
      f"--screenshot={png}",f"file://{hp}"],check=True,capture_output=True)
    print("OK",png)
print("Terminé.")
