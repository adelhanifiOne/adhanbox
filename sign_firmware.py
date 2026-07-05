#!/usr/bin/env python3
"""Signe le firmware AdhanBox V2 pour l'OTA signé.

Modèle attendu par la lib Update de l'ESP32 (UPDATE_SIGN + UpdaterECDSAVerifier):
  image_signee = [firmware.bin] + [trailer de 512 octets]
  trailer = signature ECDSA P-256 au format DER (SEQUENCE{r,s}), zero-paddée à 512.
Le device hashe SHA-256 la partie firmware (taille totale - 512) et vérifie le
trailer avec la clé publique embarquée.

Usage: python3 sign_firmware.py <firmware.bin> [sortie.bin]
Clé privée: keys/ota_private.pem (JAMAIS commitée — voir .gitignore).
"""
import os, sys, subprocess, tempfile

SIG_TRAILER_SIZE = 512  # taille fixe attendue par la lib (Updater.cpp)
PRIV_KEY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "keys", "ota_private.pem")


def sign(firmware_path, out_path):
    if not os.path.exists(PRIV_KEY):
        sys.exit(f"[ERREUR] clé privée absente: {PRIV_KEY}\n"
                 f"Génère-la: openssl ecparam -name prime256v1 -genkey -noout -out {PRIV_KEY}")
    fw = open(firmware_path, "rb").read()

    # 1) signature ECDSA P-256 / SHA-256 au format DER (openssl produit du DER)
    with tempfile.NamedTemporaryFile(delete=False) as t:
        sig_path = t.name
    subprocess.run(["openssl", "dgst", "-sha256", "-sign", PRIV_KEY, "-out", sig_path, firmware_path],
                   check=True)
    sig = open(sig_path, "rb").read()
    os.unlink(sig_path)
    if len(sig) > SIG_TRAILER_SIZE:
        sys.exit(f"[ERREUR] signature ({len(sig)}o) > trailer ({SIG_TRAILER_SIZE}o)")

    # 2) trailer = signature DER + zero-padding jusqu'à 512
    trailer = sig + b"\x00" * (SIG_TRAILER_SIZE - len(sig))

    # 3) image signée = firmware + trailer
    open(out_path, "wb").write(fw + trailer)
    print(f"[OK] {out_path}")
    print(f"     firmware={len(fw)} o + trailer={SIG_TRAILER_SIZE} o "
          f"(signature DER={len(sig)} o) = {len(fw)+SIG_TRAILER_SIZE} o")


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: sign_firmware.py <firmware.bin> [sortie.bin]")
    fw = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else fw  # par défaut: signe en place
    sign(fw, out)


if __name__ == "__main__":
    main()
