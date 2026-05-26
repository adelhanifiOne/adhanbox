#!/usr/bin/env python3
"""
Deploy hub_backend to Raspberry Pi and restart the service.
Run: python deploy.py
"""
import os
import sys
import getpass

try:
    import paramiko
except ImportError:
    print("Installing paramiko...")
    os.system(f"{sys.executable} -m pip install paramiko")
    import paramiko

HOST = "raspberrypi.local"
USER = "funroom"
REMOTE_BASE = "/home/funroom/hub_backend"
LOCAL_BASE = os.path.join(os.path.dirname(__file__), "hub_backend")

FILES = [
    "config.py",
    "main.py",
    "requirements.txt",
    "models/schemas.py",
    "models/db_models.py",
    "routers/devices.py",
    "routers/prayers.py",
    "routers/azkar.py",
    "routers/adhans.py",
    "routers/automation.py",
    "routers/voice.py",
    "services/mqtt_client.py",
    "services/prayer_times.py",
    "services/automation_engine.py",
    "services/mawaqit_service.py",
    "services/prayer_scheduler.py",
    "services/prayer_scheduler.py",
    "services/azkar_audio.py",
    "services/voice_assistant.py",
    "services/rag_engine.py",
    "routers/assistant.py",
    "services/speaker_state.py",
    "services/wakeword_service.py",
    "services/tuya_service.py",
    "routers/lsc.py",
    "routers/tuya_bulbs.py",
    "routers/tuya_strip.py",
]

KEY_PATH = os.path.expanduser("~/.ssh/id_ed25519")


def connect(password=None):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    kwargs = dict(hostname=HOST, username=USER, timeout=10)
    if os.path.exists(KEY_PATH) and not password:
        kwargs["key_filename"] = KEY_PATH
    else:
        kwargs["password"] = password
    client.connect(**kwargs)
    # Keepalive toutes les 30s pour éviter timeout SSH pendant pip install
    client.get_transport().set_keepalive(30)
    return client


def run(client, cmd, timeout=120):
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    stdout.channel.settimeout(timeout)
    try:
        out = stdout.read().decode().strip()
    except (TimeoutError, Exception):
        out = ""
    try:
        err = stderr.read().decode().strip()
    except (TimeoutError, Exception):
        err = ""
    if out:
        print(f"  > {out}")
    if err:
        print(f"  ! {err}")
    return out


def upload(sftp, local_rel, remote_rel):
    local = os.path.join(LOCAL_BASE, local_rel.replace("/", os.sep))
    remote = f"{REMOTE_BASE}/{remote_rel}"
    if not os.path.exists(local):
        print(f"  skip (not found): {local_rel}")
        return
    remote_dir = remote.rsplit("/", 1)[0]
    try:
        sftp.mkdir(remote_dir)
    except OSError:
        pass
    sftp.put(local, remote)
    print(f"  OK {local_rel}")


def setup_ssh_key(client):
    pub = open(KEY_PATH + ".pub").read().strip()
    run(client, "mkdir -p ~/.ssh && chmod 700 ~/.ssh")
    run(client, f"grep -qxF '{pub}' ~/.ssh/authorized_keys 2>/dev/null || echo '{pub}' >> ~/.ssh/authorized_keys")
    run(client, "chmod 600 ~/.ssh/authorized_keys")
    print("  OK Cle SSH ajoutee — connexions futures sans mot de passe")


def main():
    password = None
    print(f"Connexion à {USER}@{HOST}...")
    try:
        client = connect()
    except Exception:
        password = getpass.getpass(f"Mot de passe pour {USER}@{HOST}: ")
        client = connect(password=password)

    if password and os.path.exists(KEY_PATH):
        print("\nConfig de la clé SSH pour les prochains déploiements...")
        setup_ssh_key(client)

    print("\nEnvoi des fichiers backend...")
    sftp = client.open_sftp()
    for f in FILES:
        upload(sftp, f, f)
    sftp.close()

    print("\nMise à jour des dépendances Python...")
    run(client, "~/hub_backend/venv/bin/pip install -q -r ~/hub_backend/requirements.txt", timeout=300)
    print("  OK dépendances")

    print("\nRedémarrage du backend...")
    import time
    run(client, "pkill -9 -f 'uvicorn main:app' 2>/dev/null || true")
    time.sleep(2)
    # Confirm port is free before starting
    run(client, "fuser -k 8000/tcp 2>/dev/null || true")
    time.sleep(1)
    run(client,
        "cd ~/hub_backend && nohup ~/hub_backend/venv/bin/uvicorn main:app "
        "--host 0.0.0.0 --port 8000 "
        "> ~/hub_backend/uvicorn.log 2>&1 & disown; echo ok",
        timeout=15)
    print("  OK uvicorn redémarre (log: ~/hub_backend/uvicorn.log)")

    print("\nVérification de santé...")
    time.sleep(5)
    out = run(client, "curl -s http://localhost:8000/health")
    if '"ok"' in out or "ok" in out.lower():
        print("  OK Backend en ligne")
    else:
        print(f"  ! Réponse inattendue: {out}")
        print("    Consulter le log: ssh funroom@172.20.10.4 tail -30 ~/hub_backend/uvicorn.log")

    client.close()
    print("\nDéploiement terminé !")


if __name__ == "__main__":
    main()
