#!/usr/bin/env python3
"""Maintenance du firmware AdhanBox V2 (adhanbox_v2/adhanbox_v2.ino).

⚠️  CHANGEMENT IMPORTANT (2026-07)
Le V2 N'EST PLUS généré à partir du V1. Le moteur audio I2S pur a divergé du
DFPlayer de la V1 (renommage complet dfplayer→audio / classe I2SAudio,
détection de fin de lecture par polling au lieu des événements série,
~100 lignes de printDetail supprimées). adhanbox_v2/adhanbox_v2.ino est
désormais la SOURCE DE VÉRITÉ, maintenue à la main.

L'ancien générateur régénérait la version « shim » (encore truffée de
DFPlayer, LED_NUM=16, version 2.0.0) : le relancer écrasait le firmware pur et
provoquait une régression. Ce script ne régénère donc plus rien depuis la V1.

Il se contente maintenant, de façon idempotente :
  1. GARDE-FOU : refuse de continuer s'il reste la moindre trace de DFPlayer
     (= le .ino est une vieille version V1/shim périmée).
  2. Stampe LED_NUM (constante ci-dessous).
  3. Synchronise TOUTES les chaînes de version sur firmware_version_v2.json
     (commentaire d'entête, message série de démarrage, et les JSON servis par
     /api/firmware/version et /api/info — sinon le device rapporte une
     mauvaise version et l'app propose des MAJ en boucle).

NE TOUCHE JAMAIS au canal V1 (adhanbox/adhanbox.ino, firmware_version.json)
=> les AdhanBox V1 ne reçoivent pas ces changements.
"""
import os, re, sys, json

INO = "adhanbox_v2/adhanbox_v2.ino"
CONFIG = "firmware_version_v2.json"

# ── Paramètres du build V2 (seul endroit à éditer) ─────────────────────────
LED_NUM = 25   # nombre de LEDs du bandeau
# La version est lue depuis CONFIG (bumpée par deploy_firmware_v2.py) pour
# garder une source unique de vérité.


def fail(msg):
    sys.exit("ABORT: " + msg)


def sub1(text, pattern, repl, what):
    """Remplace 1 occurrence, abort si le compte n'est pas exactement 1."""
    new, n = re.subn(pattern, repl, text, count=1)
    if n != 1:
        fail(f"motif « {what} » trouvé {n}x (attendu 1)")
    return new


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    if not os.path.exists(INO):
        fail(INO + " introuvable")
    if not os.path.exists(CONFIG):
        fail(CONFIG + " introuvable")

    version = json.load(open(CONFIG, encoding="utf-8")).get("version")
    if not version:
        fail("champ 'version' absent de " + CONFIG)

    t = open(INO, encoding="utf-8").read()

    # 1) GARDE-FOU anti-régression : plus aucune trace de DFPlayer autorisée.
    for bad in ("DFPlayer", "DFRobot", "dfplayer", "DFPLAYER", "Serial2"):
        if bad in t:
            fail(f"« {bad} » présent dans {INO} : c'est une version V1/shim "
                 f"périmée. Restaure la version pure avec :\n"
                 f"    git checkout HEAD -- {INO}")

    # 2) LED_NUM
    t = sub1(t, r'(#define LED_NUM )\d+', rf'\g<1>{LED_NUM}', "#define LED_NUM")

    # 3) version : commentaire d'entête
    t = sub1(t, r'(//Version: )\d+\.\d+\.\d+', rf'\g<1>{version}',
             "//Version:")
    # 3b) message série de démarrage
    t = sub1(t, r'(AdhanBox V2 firmware v)\d+\.\d+\.\d+( starting)',
             rf'\g<1>{version}\g<2>', "message de démarrage")
    # 3c) chaînes de version servies en JSON (device -> app). Il y en a 2 :
    #     /api/firmware/version et /api/info. On remplace TOUTES les occurrences
    #     de \"version\":\"X.Y.Z\" — c'est ce que l'app compare pour l'OTA.
    t, n = re.subn(r'(\\"version\\":\\")\d+\.\d+\.\d+(\\")',
                   rf'\g<1>{version}\g<2>', t)
    if n < 1:
        fail("aucune chaîne JSON \\\"version\\\" trouvée (device->app)")

    open(INO, "w", encoding="utf-8").write(t)
    print(f"OK -> {INO}")
    print(f"     LED_NUM={LED_NUM}  version={version}  "
          f"({n} chaîne(s) JSON de version synchronisée(s))")


if __name__ == "__main__":
    main()
