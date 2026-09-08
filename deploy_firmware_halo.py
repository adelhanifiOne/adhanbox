#!/usr/bin/env python3
"""Déploiement du firmware Halo (canal séparé, ESP32-C3).

Compile halo/firmware/halo/ -> build_temp_halo/halo.ino.bin, signe le binaire,
met à jour firmware_version_halo.json, commit + push.

NE TOUCHE JAMAIS aux canaux V1, V2, V3 : l'app choisit le canal d'après le
champ hardware ("halo") de /api/firmware/version.
"""
import os, sys, json, re, subprocess

CONFIG = 'firmware_version_halo.json'
SKETCH_DIR = 'halo/firmware/halo'
INO = 'halo/firmware/halo/halo.ino'
BUILD_DIR = 'build_temp_halo'
BIN = 'build_temp_halo/halo.ino.bin'
# ESP32-C3-MINI-1 : 4 Mo, pas de PSRAM, USB natif -> Serial sur le CDC (seul port serie du Halo)
FQBN = 'esp32:esp32:esp32c3:PartitionScheme=min_spiffs,CDCOnBoot=cdc'


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
    print("     Halo — DÉPLOIEMENT (canal séparé)     ")
    print("=" * 50)

    if not os.path.exists(CONFIG):
        sys.exit(f"[ERREUR] {CONFIG} introuvable.")
    if not os.path.exists(INO):
        sys.exit(f"[ERREUR] {INO} introuvable.")

    cfg = json.load(open(CONFIG, encoding='utf-8'))
    cur = cfg.get('version', '1.0.0')
    print(f"-> Version Halo actuelle : {cur}")

    parts = cur.split('.')
    suggested = '.'.join(parts[:2] + [str(int(parts[2]) + 1)]) if len(parts) == 3 else cur + '.1'
    new_ver = input(f"Version à déployer (Entrée pour '{suggested}') : ").strip() or suggested
    changelog = input("Changelog : ").strip() or f"Halo — mise à jour v{new_ver}"

    cli = check_arduino_cli()
    if not cli:
        sys.exit("[ERREUR] arduino-cli requis (brew install arduino-cli).")

    # 1) Manifeste Halo (on conserve hardware:halo et l'URL)
    cfg['version'] = new_ver
    cfg['changelog'] = changelog
    cfg.setdefault('hardware', 'halo')
    with open(CONFIG, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f"[OK] {CONFIG} mis à jour.")

    # 2) Version dans le .ino : en-tete //Version: et la constante HALO_VERSION
    s = open(INO, encoding='utf-8').read()
    s = re.sub(r'//\s*Version:\s*[0-9.]+', f'//Version: {new_ver}', s, count=1)
    s = re.sub(r'#define HALO_VERSION\s+"[0-9.]+"', f'#define HALO_VERSION  "{new_ver}"', s, count=1)
    open(INO, 'w', encoding='utf-8').write(s)
    print(f"[OK] Version mise à jour dans {INO}.")

    # 3) Compilation
    print("\nCompilation Halo (ESP32-C3)...")
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

    # 4) Git (uniquement les fichiers Halo)
    print("\nPublication Git (canal Halo)...")
    try:
        subprocess.run(['git', 'add', '-f', BIN], check=True)
        subprocess.run(['git', 'add', CONFIG, INO], check=True)
        subprocess.run(['git', 'commit', '-m', f'Release firmware Halo v{new_ver}'], check=True)
        subprocess.run(['git', 'push', 'origin', 'main'], check=True)
        print("\n[SUCCÈS] Firmware Halo publié (V1, V2, V3 intacts).")
    except Exception as e:
        sys.exit(f"\n[ERREUR] Git : {e}")

    print(f"\nDéploiement Halo v{new_ver} terminé. Canal : {CONFIG}")


if __name__ == '__main__':
    main()
