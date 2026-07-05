#!/usr/bin/env python3
"""Déploiement du firmware AdhanBox V2 (canal séparé).

Compile adhanbox_v2/ -> build_temp_v2/adhanbox_v2.ino.bin,
met à jour firmware_version_v2.json, commit + push.

NE TOUCHE JAMAIS au canal V1 (firmware_version.json / adhanbox/adhanbox.ino)
=> les AdhanBox V1 ne reçoivent pas cette mise à jour.
"""
import os, sys, json, re, subprocess

CONFIG = 'firmware_version_v2.json'
SKETCH_DIR = 'adhanbox_v2'
INO = 'adhanbox_v2/adhanbox_v2.ino'
BUILD_DIR = 'build_temp_v2'
BIN = 'build_temp_v2/adhanbox_v2.ino.bin'
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
    print("     AdhanBox V2 — DÉPLOIEMENT (canal séparé)     ")
    print("=" * 50)

    if not os.path.exists(CONFIG):
        sys.exit(f"[ERREUR] {CONFIG} introuvable.")
    if not os.path.exists(INO):
        sys.exit(f"[ERREUR] {INO} introuvable (lance d'abord make_v2_firmware.py).")

    cfg = json.load(open(CONFIG, encoding='utf-8'))
    cur = cfg.get('version', '2.0.0')
    print(f"-> Version V2 actuelle : {cur}")

    parts = cur.split('.')
    suggested = '.'.join(parts[:2] + [str(int(parts[2]) + 1)]) if len(parts) == 3 else cur + '.1'
    new_ver = input(f"Version à déployer (Entrée pour '{suggested}') : ").strip() or suggested
    changelog = input("Changelog : ").strip() or f"AdhanBox V2 — mise à jour v{new_ver}"

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

    # 3) Compilation
    print("\nCompilation V2...")
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
    print("\nPublication Git (canal V2)...")
    try:
        subprocess.run(['git', 'add', '-f', BIN], check=True)
        subprocess.run(['git', 'add', CONFIG, INO], check=True)
        subprocess.run(['git', 'commit', '-m', f'Release firmware V2 v{new_ver}'], check=True)
        subprocess.run(['git', 'push', 'origin', 'main'], check=True)
        print("\n[SUCCÈS] Firmware V2 publié (V1 intact).")
    except Exception as e:
        sys.exit(f"\n[ERREUR] Git : {e}")

    print(f"\nDéploiement V2 v{new_ver} terminé. Canal : {CONFIG}")


if __name__ == '__main__':
    main()
