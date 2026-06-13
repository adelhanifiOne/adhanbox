#!/usr/bin/env python3
import os
import sys
import json
import re
import subprocess

def check_arduino_cli():
    # Paths to look for arduino-cli
    paths = ['/opt/homebrew/bin/arduino-cli', '/usr/local/bin/arduino-cli', 'arduino-cli']
    for p in paths:
        try:
            res = subprocess.run([p, 'version'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if res.returncode == 0:
                return p
        except FileNotFoundError:
            continue
    return None

def install_arduino_cli():
    print("arduino-cli n'est pas détecté sur votre système.")
    print("Tentative d'installation via Homebrew...")
    try:
        subprocess.run(['brew', 'install', 'arduino-cli'], check=True)
        p = check_arduino_cli()
        if p:
            print("arduino-cli a été installé avec succès.")
            return p
    except Exception as e:
        print(f"Erreur lors de l'installation de arduino-cli : {e}")
    return None

def main():
    # Change CWD to the script directory to run relative to the workspace root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    print("==================================================")
    print("       AdhanBox - DÉPLOIEMENT DU FIRMWARE        ")
    print("==================================================")

    # 1. Lire la version actuelle
    config_path = 'firmware_version.json'
    if not os.path.exists(config_path):
        print(f"[ERREUR] Fichier {config_path} introuvable.")
        sys.exit(1)

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config_data = json.load(f)
    except Exception as e:
        print(f"[ERREUR] Impossible de lire {config_path} : {e}")
        sys.exit(1)

    current_ver = config_data.get('version', '1.4.0')
    print(f"-> Version actuelle détectée : {current_ver}")

    # Calculer automatiquement la version suivante (Incrément du patch)
    parts = current_ver.split('.')
    if len(parts) == 3:
        try:
            parts[2] = str(int(parts[2]) + 1)
        except ValueError:
            parts[2] = '1'
        suggested_ver = '.'.join(parts)
    else:
        suggested_ver = current_ver + '.1'

    # Demander confirmation de la version (Entrée pour valider directement)
    print(f"-> Nouvelle version suggérée : {suggested_ver}")
    new_ver = input(f"Saisissez la version à déployer (Entrée pour '{suggested_ver}') : ").strip()
    if not new_ver:
        new_ver = suggested_ver

    changelog = input("Description de la mise à jour (Changelog) : ").strip()
    if not changelog:
        changelog = f"Mise à jour automatique vers v{new_ver}"

    # 2. Vérifier/installer arduino-cli
    cli_path = check_arduino_cli()
    if not cli_path:
        cli_path = install_arduino_cli()
        if not cli_path:
            print("[ERREUR] arduino-cli requis. Veuillez l'installer manuellement.")
            sys.exit(1)

    # 3. Mettre à jour firmware_version.json
    config_data['version'] = new_ver
    config_data['changelog'] = changelog
    try:
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config_data, f, indent=2, ensure_ascii=False)
            f.write('\n')
        print(f"[OK] Fichier {config_path} mis à jour.")
    except Exception as e:
        print(f"[ERREUR] Échec de la mise à jour de {config_path} : {e}")
        sys.exit(1)

    # 4. Mettre à jour adhanbox/adhanbox.ino
    ino_path = 'adhanbox/adhanbox.ino'
    if not os.path.exists(ino_path):
        print(f"[ERREUR] Fichier {ino_path} introuvable.")
        sys.exit(1)

    try:
        with open(ino_path, 'r', encoding='utf-8') as f:
            ino_content = f.read()

        # Remplacement des commentaires de version
        ino_content = re.sub(
            r'//\s*Version:\s*[0-9\.]+',
            f'//Version: {new_ver}',
            ino_content
        )
        # Remplacement des JSON version strings dans le code C++
        ino_content = re.sub(
            r'"\{\\\"version\\\":\\"[0-9\.]+\\"',
            f'"{{\\\"version\\\":\\"{new_ver}\\"',
            ino_content
        )

        with open(ino_path, 'w', encoding='utf-8') as f:
            f.write(ino_content)
        print(f"[OK] Version mise à jour dans {ino_path}.")
    except Exception as e:
        print(f"[ERREUR] Impossible de modifier {ino_path} : {e}")
        sys.exit(1)

    # 5. Compilation avec arduino-cli
    print("\nCompilation du firmware avec arduino-cli...")
    os.makedirs('build_temp', exist_ok=True)

    fqbn = 'esp32:esp32:esp32s3:PartitionScheme=min_spiffs'
    lib_path = os.path.expanduser('~/Documents/Arduino/libraries')

    compile_cmd = [
        cli_path, 'compile',
        '--fqbn', fqbn,
        '--libraries', lib_path,
        '--output-dir', 'build_temp',
        'adhanbox'
    ]

    print(f"Exécution : {' '.join(compile_cmd)}")
    
    try:
        compile_res = subprocess.run(compile_cmd)
        if compile_res.returncode != 0:
            print("\n[ERREUR] La compilation a échoué. Veuillez vérifier les erreurs ci-dessus.")
            sys.exit(1)
        print("[OK] Compilation réussie. Le fichier binaire est généré dans build_temp/adhanbox.ino.bin")
    except Exception as e:
        print(f"[ERREUR] Échec de la commande de compilation : {e}")
        sys.exit(1)

    # 6. Git commit et push
    print("\nEnvoi de la mise à jour sur GitHub...")
    try:
        # On force l'ajout du fichier binaire car *.bin est présent dans le .gitignore
        subprocess.run(['git', 'add', '-f', 'build_temp/adhanbox.ino.bin'], check=True)
        subprocess.run(['git', 'add', 'firmware_version.json', ino_path], check=True)
        subprocess.run(['git', 'commit', '-m', f'Release firmware v{new_ver}'], check=True)
        subprocess.run(['git', 'push', 'origin', 'main'], check=True)
        print("\n[SUCCÈS] Code source et binaire poussés sur GitHub !")
    except Exception as e:
        print(f"\n[ERREUR] Échec de la publication Git : {e}")
        sys.exit(1)

    print(f"\nDéploiement terminé avec succès ! La version v{new_ver} est en ligne.")
    input("\nAppuyez sur Entrée pour quitter...")

if __name__ == '__main__':
    main()
