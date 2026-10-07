#!/usr/bin/env python3
"""Déploiement du firmware AdhanBox V3 (canal séparé).

Compile adhanbox_v3/ -> build_temp_v3/adhanbox_v3.ino.bin,
met à jour firmware_version_v3.json, commit + push.

NE TOUCHE JAMAIS aux canaux V1 NI V2 => les AdhanBox V1/V2 (RTC DS3231)
ne recoivent JAMAIS ce firmware (driver RTC RX8025T incompatible).
"""
import os, sys, json, re, subprocess

CONFIG = 'firmware_version_v3.json'
SKETCH_DIR = 'adhanbox_v3'
INO = 'adhanbox_v3/adhanbox_v3.ino'
BUILD_DIR = 'build_temp_v3'
BIN = 'build_temp_v3/adhanbox_v3.ino.bin'
FQBN = 'esp32:esp32:esp32s3:PartitionScheme=min_spiffs,PSRAM=enabled'  # QSPI (FH4R2)


def check_arduino_cli():
    for p in ['/opt/homebrew/bin/arduino-cli', '/usr/local/bin/arduino-cli', 'arduino-cli']:
        try:
            if subprocess.run([p, 'version'], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True).returncode == 0:
                return p
        except FileNotFoundError:
            continue
    return None


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    print("=" * 50)
    print("     AdhanBox V3 — DÉPLOIEMENT (canal séparé)     ")
    print("=" * 50)

    if not os.path.exists(CONFIG):
        sys.exit(f"[ERREUR] {CONFIG} introuvable.")
    if not os.path.exists(INO):
        sys.exit(f"[ERREUR] {INO} introuvable (sketch V3 dedie).")

    cfg = json.load(open(CONFIG, encoding='utf-8'))
    cur = cfg.get('version', '2.0.0')
    print(f"-> Version V3 actuelle : {cur}")

    parts = cur.split('.')
    suggested = '.'.join(parts[:2] + [str(int(parts[2]) + 1)]) if len(parts) == 3 else cur + '.1'
    new_ver = input(f"Version à déployer (Entrée pour '{suggested}') : ").strip() or suggested
    changelog = input("Changelog : ").strip() or f"AdhanBox V3 — mise à jour v{new_ver}"

    cli = check_arduino_cli()
    if not cli:
        sys.exit("[ERREUR] arduino-cli requis (brew install arduino-cli).")

    # 1) Manifeste V2 (on conserve hardware:v2 et l'URL)
    cfg['version'] = new_ver
    cfg['changelog'] = changelog
    cfg.setdefault('hardware', 'v2')
    with open(CONFIG, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f"[OK] {CONFIG} mis à jour.")

    # 2) Version dans le .ino V2 (préserve le marqueur hardware après la version)
    s = open(INO, encoding='utf-8').read()
    s = re.sub(r'//\s*Version:\s*[0-9.]+', f'//Version: {new_ver}', s, count=1)
    s = re.sub(r'(\\"version\\":\\")[0-9.]+(\\")', rf'\g<1>{new_ver}\g<2>', s)
    open(INO, 'w', encoding='utf-8').write(s)
    print(f"[OK] Version mise à jour dans {INO}.")

    # 3) Compilation — avec le correctif du pilote SD du core (07/10/2026) :
    # sans lui, certaines cartes SD voient leurs ecritures declarees en echec
    # alors qu'elles sont faites, et les voix ne se telechargent jamais. Le
    # correctif vit dans le core installe ; on l'applique/verifie avant de
    # compiler, comme le banc.
    sys.path.insert(0, 'outils_production')
    import sd_diskio_diag as sdd
    sdd.appliquer(); sdd.corriger()
    if sdd.MARQUE_FIX not in open(sdd.CHEMIN, encoding='utf-8').read():
        sys.exit("\n[ERREUR] correctif du pilote SD absent du core : publication refusee.")
    print("[OK] Pilote SD du core corrige.")
    print("\nCompilation V3...")
    os.makedirs(BUILD_DIR, exist_ok=True)
    lib = os.path.expanduser('~/Documents/Arduino/libraries')
    cmd = [cli, 'compile', '--fqbn', FQBN, '--libraries', lib,
           '--output-dir', BUILD_DIR, SKETCH_DIR]
    print("Exécution :", ' '.join(cmd))
    if subprocess.run(cmd).returncode != 0:
        sys.exit("\n[ERREUR] Compilation échouée.")
    if not os.path.exists(BIN):
        sys.exit(f"\n[ERREUR] Binaire {BIN} introuvable après compilation.")
    print(f"[OK] Binaire généré : {BIN}")

    # 3b) [SECU] Signature OTA : le firmware (UPDATE_SIGN) REFUSE tout binaire non
    # signe par la cle privee. On signe le .bin en place (firmware + trailer 512o)
    # avant publication. Sans cette etape, l'OTA echoue cote device (verif KO).
    if os.path.exists('keys/ota_private.pem'):
        print("\nSignature OTA du binaire...")
        if subprocess.run([sys.executable, 'sign_firmware.py', BIN]).returncode != 0:
            sys.exit("\n[ERREUR] Signature echouee.")
    else:
        print("[ATTENTION] keys/ota_private.pem absent : binaire NON signe "
              "(les devices en firmware signe le refuseront).")

    # 4) Git (uniquement les fichiers V2)
    print("\nPublication Git (canal V3)...")
    try:
        subprocess.run(['git', 'add', '-f', BIN], check=True)
        subprocess.run(['git', 'add', CONFIG, INO], check=True)
        subprocess.run(['git', 'commit', '-m', f'Release firmware V3 v{new_ver}'], check=True)
        subprocess.run(['git', 'push', 'origin', 'main'], check=True)
        print("\n[SUCCÈS] Firmware V3 publié (V1 et V2 intacts).")
    except Exception as e:
        sys.exit(f"\n[ERREUR] Git : {e}")

    print(f"\nDéploiement V3 v{new_ver} terminé. Canal : {CONFIG}")


if __name__ == '__main__':
    main()
