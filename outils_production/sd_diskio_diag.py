#!/usr/bin/env python3
"""Instrumente le pilote SD (SPI) du core esp32 pour savoir OU et POURQUOI une
ecriture est refusee par la carte : etape, reponse de la carte, secteur, et
la plus longue attente « carte occupee » observee.

Le pilote vit dans le core installe (~/Library/Arduino15/...), pas dans le
depot : ce script applique le patch de facon idempotente et garde l'original
en .orig. `--retirer` remet l'original. Ecrit le 07/10/2026 : deux box V3
refusaient des ecritures au meme octet (61 440, 77 824, 847 872...) alors que
la carte etait saine sur le Mac ; sans la reponse de la carte, impossible de
dire si c'est un CRC de commande, un jeton de donnees ou un statut.

Compteurs exposes au croquis (extern "C" volatile uint32_t ...) :
  sd_diag_echecs       nombre d'echecs d'ecriture depuis le demarrage
  sd_diag_etape        1 select, 2 ACMD23, 3 CMD25, 4 jeton de donnees,
                       5 attente occupee, 6 STOP, 7 statut R2, 8 CMD24
  sd_diag_token        reponse de la carte a cette etape (R1 / jeton / R2)
  sd_diag_secteur      secteur vise
  sd_diag_busy_max_ms  attente « occupee » maximale vue dans sdWait
"""
import os, shutil, sys

CHEMIN = os.path.expanduser(
    '~/Library/Arduino15/packages/esp32/hardware/esp32/3.3.11/libraries/SD/src/sd_diskio.cpp')
MARQUE = '[ADHANBOX DIAG]'

def rep(s, a, b, n=1):
    assert s.count(a) == n, 'ancre introuvable ou multiple (%d) : %r' % (s.count(a), a[:70])
    return s.replace(a, b)

def appliquer():
    s = open(CHEMIN, encoding='utf-8').read()
    if MARQUE in s:
        print('deja instrumente'); return
    if not os.path.exists(CHEMIN + '.orig'):
        shutil.copyfile(CHEMIN, CHEMIN + '.orig')
    # globals + mesure de l'attente occupee
    s = rep(s, "bool sdWait(uint8_t pdrv, int timeout) {\n  char resp;\n  uint32_t start = millis();\n",
            "// %s compteurs lisibles par le croquis\n"
            "extern \"C\" {\n"
            "volatile uint32_t sd_diag_echecs = 0, sd_diag_secteur = 0, sd_diag_busy_max_ms = 0;\n"
            "volatile uint8_t  sd_diag_etape = 0, sd_diag_token = 0;\n"
            "}\n"
            "static inline void sdDiag(uint8_t etape, uint8_t token, unsigned long long secteur) {\n"
            "  sd_diag_echecs++; sd_diag_etape = etape; sd_diag_token = token; sd_diag_secteur = (uint32_t)secteur;\n"
            "}\n"
            "bool sdWait(uint8_t pdrv, int timeout) {\n  char resp;\n  uint32_t start = millis();\n" % MARQUE)
    s = rep(s, "  } while (resp == 0x00 && (millis() - start) < (unsigned int)timeout);\n\n  if (!resp) {\n    log_w(\"Wait Failed\");\n  }\n",
            "  } while (resp == 0x00 && (millis() - start) < (unsigned int)timeout);\n"
            "  { uint32_t d = millis() - start; if (d > sd_diag_busy_max_ms) sd_diag_busy_max_ms = d; }\n"
            "  if (!resp) {\n    log_w(\"Wait Failed\");\n  }\n")
    # sdWriteSector (CMD24)
    s = rep(s, """bool sdWriteSector(uint8_t pdrv, const char *buffer, unsigned long long sector) {
  for (int f = 0; f < 3; f++) {
    if (!sdSelectCard(pdrv)) {
      return false;
    }
    if (!sdCommand(pdrv, WRITE_BLOCK_SINGLE, (s_cards[pdrv]->type == CARD_SDHC) ? sector : sector << 9, NULL)) {
      char token = sdWriteBytes(pdrv, buffer, 0xFE);
      sdDeselectCard(pdrv);

      if (token == 0x0A) {
        continue;
      } else if (token == 0x0C) {
        return false;
      }

      unsigned int resp;
      if (sdTransaction(pdrv, SEND_STATUS, 0, &resp) || resp) {
        return false;
      }
      return true;
    } else {
      break;
    }
  }
  sdDeselectCard(pdrv);
  return false;
}""", """bool sdWriteSector(uint8_t pdrv, const char *buffer, unsigned long long sector) {
  char r1 = 0;
  for (int f = 0; f < 3; f++) {
    if (!sdSelectCard(pdrv)) {
      sdDiag(1, 0, sector);
      return false;
    }
    if (!(r1 = sdCommand(pdrv, WRITE_BLOCK_SINGLE, (s_cards[pdrv]->type == CARD_SDHC) ? sector : sector << 9, NULL))) {
      char token = sdWriteBytes(pdrv, buffer, 0xFE);
      sdDeselectCard(pdrv);

      if (token == 0x0A) {
        continue;
      } else if (token == 0x0C) {
        sdDiag(4, token, sector);
        return false;
      }

      unsigned int resp;
      if (sdTransaction(pdrv, SEND_STATUS, 0, &resp) || resp) {
        sdDiag(7, (uint8_t)resp, sector);
        return false;
      }
      return true;
    } else {
      sdDiag(8, r1, sector);
      break;
    }
  }
  sdDeselectCard(pdrv);
  return false;
}""")
    # sdWriteSectors (CMD25)
    s = rep(s, """    if (card->type != CARD_MMC) {
      if (sdTransaction(pdrv, SET_WR_BLK_ERASE_COUNT, currentCount, NULL)) {
        return false;
      }
    }

    if (!sdSelectCard(pdrv)) {
      return false;
    }

    if (!sdCommand(pdrv, WRITE_BLOCK_MULTIPLE, (card->type == CARD_SDHC) ? currentSector : currentSector << 9, NULL)) {
      do {
        token = sdWriteBytes(pdrv, currentBuffer, 0xFC);
        if (token != 0x05) {
          f++;
          break;
        }
        currentBuffer += 512;
        f = 0;
      } while (--currentCount);

      if (!sdWait(pdrv, 500)) {
        break;
      }

      if (currentCount == 0) {
        sdStop(pdrv);
        sdDeselectCard(pdrv);

        unsigned int resp;
        if (sdTransaction(pdrv, SEND_STATUS, 0, &resp) || resp) {
          return false;
        }
        return true;
      } else {
        if (sdCommand(pdrv, STOP_TRANSMISSION, 0, NULL)) {
          break;
        }
""", """    if (card->type != CARD_MMC) {
      char r1 = sdTransaction(pdrv, SET_WR_BLK_ERASE_COUNT, currentCount, NULL);
      if (r1) {
        sdDiag(2, r1, currentSector);
        return false;
      }
    }

    if (!sdSelectCard(pdrv)) {
      sdDiag(1, 0, currentSector);
      return false;
    }

    char r1c = sdCommand(pdrv, WRITE_BLOCK_MULTIPLE, (card->type == CARD_SDHC) ? currentSector : currentSector << 9, NULL);
    if (!r1c) {
      do {
        token = sdWriteBytes(pdrv, currentBuffer, 0xFC);
        if (token != 0x05) {
          sdDiag(4, token, currentSector + (count - currentCount));
          f++;
          break;
        }
        currentBuffer += 512;
        f = 0;
      } while (--currentCount);

      if (!sdWait(pdrv, 500)) {
        sdDiag(5, 0, currentSector);
        break;
      }

      if (currentCount == 0) {
        sdStop(pdrv);
        sdDeselectCard(pdrv);

        unsigned int resp;
        if (sdTransaction(pdrv, SEND_STATUS, 0, &resp) || resp) {
          sdDiag(7, (uint8_t)resp, currentSector);
          return false;
        }
        return true;
      } else {
        char r1s = sdCommand(pdrv, STOP_TRANSMISSION, 0, NULL);
        if (r1s) {
          sdDiag(6, r1s, currentSector);
          break;
        }
""")
    s = rep(s, """          currentBuffer = buffer + (writtenBlocks << 9);
          currentSector = sector + writtenBlocks;
          currentCount = count - writtenBlocks;
          continue;
        } else {
          break;
        }
      }
    } else {
      break;
    }
  }
  sdDeselectCard(pdrv);
  return false;
}""", """          currentBuffer = buffer + (writtenBlocks << 9);
          currentSector = sector + writtenBlocks;
          currentCount = count - writtenBlocks;
          continue;
        } else {
          break;
        }
      }
    } else {
      sdDiag(3, r1c, currentSector);
      break;
    }
  }
  sdDeselectCard(pdrv);
  return false;
}""")
    open(CHEMIN, 'w', encoding='utf-8').write(s)
    print('pilote SD instrumente :', CHEMIN)

MARQUE_FIX = '[ADHANBOX CORRECTIF STOP_TRAN]'

def corriger():
    """Le vrai defaut, trouve le 07/10/2026 grace aux compteurs : apres le jeton
    de fin (Stop Tran) d'une ecriture multi-blocs, le pilote n'attend PAS que
    la carte ait fini de programmer ; il enchaine SEND_STATUS. Une carte qui
    prend la ligne « occupee » un octet plus tard (c'est permis par la norme)
    recoit la commande pendant qu'elle programme, et le statut lu est un octet
    de liberation de ligne (0x01, 0x7f...) -> le pilote conclut a une erreur
    alors que les donnees SONT ecrites. Meme precaution apres un bloc unique.
    Correctif : un octet de pause puis attendre la fin de l'occupation."""
    s = open(CHEMIN, encoding='utf-8').read()
    if MARQUE_FIX in s:
        print('correctif deja applique'); return
    assert MARQUE in s, 'applique d abord l instrumentation'
    s = rep(s, """      if (currentCount == 0) {
        sdStop(pdrv);
        sdDeselectCard(pdrv);

        unsigned int resp;
        if (sdTransaction(pdrv, SEND_STATUS, 0, &resp) || resp) {
          sdDiag(7, (uint8_t)resp, currentSector);
          return false;
        }
        return true;
      } else {""", """      if (currentCount == 0) {
        sdStop(pdrv);
        // %s un octet de pause, puis on attend que la carte
        // ait fini de programmer avant toute autre commande (sinon le statut
        // lu est un octet de liberation de ligne et l'ecriture, pourtant
        // faite, est declaree en echec).
        card->spi->transfer(0xFF);
        if (!sdWait(pdrv, 2000)) {
          sdDiag(5, 1, currentSector);
          sdDeselectCard(pdrv);
          return false;
        }
        sdDeselectCard(pdrv);

        unsigned int resp;
        if (sdTransaction(pdrv, SEND_STATUS, 0, &resp) || resp) {
          sdDiag(7, (uint8_t)resp, currentSector);
          return false;
        }
        return true;
      } else {""" % MARQUE_FIX)
    s = rep(s, """      char token = sdWriteBytes(pdrv, buffer, 0xFE);
      sdDeselectCard(pdrv);

      if (token == 0x0A) {
        continue;
      } else if (token == 0x0C) {
        sdDiag(4, token, sector);
        return false;
      }
""", """      char token = sdWriteBytes(pdrv, buffer, 0xFE);
      // %s meme pause apres un bloc unique
      s_cards[pdrv]->spi->transfer(0xFF);
      if (!sdWait(pdrv, 2000)) {
        sdDiag(5, 2, sector);
        sdDeselectCard(pdrv);
        return false;
      }
      sdDeselectCard(pdrv);

      if (token == 0x0A) {
        continue;
      } else if (token == 0x0C) {
        sdDiag(4, token, sector);
        return false;
      }
""" % MARQUE_FIX)
    open(CHEMIN, 'w', encoding='utf-8').write(s)
    print('correctif Stop Tran applique :', CHEMIN)

def retirer():
    if os.path.exists(CHEMIN + '.orig'):
        shutil.copyfile(CHEMIN + '.orig', CHEMIN); print('original remis')
    else:
        print('pas de .orig : rien a remettre')

if __name__ == '__main__':
    if '--retirer' in sys.argv:
        retirer()
    else:
        appliquer()
        if '--sans-correctif' not in sys.argv:
            corriger()
