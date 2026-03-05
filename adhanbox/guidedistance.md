

* Le bouton **TEST** sur le MLU fonctionne → les lampes font rouge/blanc/couleurs
  ✅ Donc **MLU + LMCU + RS485 + lampes = OK**
* Mais **Clematis ne commande rien**
* Et **le client dit ne trouver aucune IP / pas d’accès page réseau**

➡ Conclusion : **c’est un problème réseau / configuration**, pas un problème lumière.

---




# 1) CHOIX DU SCÉNARIO : le PC est connecté comment ?


## A) “Le PC est branché DIRECTEMENT au MLU par un câble Ethernet”

➡ on travaille en **connexion directe** (meilleur cas)

## B) “Le PC est sur le réseau avion (routeur cabine / Wi-Fi cabine)”

➡ on travaille en **réseau partagé**

> ⚠️ Si le client n’est pas sûr :  regarder le câble.
>
> * câble Ethernet qui va dans le MLU = A
> * PC sur Wi-Fi / routeur = B

---

# 2) Étape obligatoire : voir l’IP actuelle du PC

Sur le PC client :

## 2.1 Ouvrir une fenêtre “Invite de commandes”

* Cliquer sur le menu Windows
* taper : `cmd`
* Entrée

## 2.2 Taper :

```bat
ipconfig
```


* **Adresse IPv4** (ex: 192.168.10.25)
* **Masque** (ex: 255.255.255.0)
* **Passerelle** (ex: 192.168.10.1)

---

# 3) Test 
Dans **Chrome** (ou Firefox), essayer ces adresses (copier-coller) :

1. `http://192.168.50.10:9994`
2. `http://192.168.20.10:9994`
3. `http://172.17.30.1:9994`
4. `http://192.168.10.10:9994`

### Résultat possible :

## ✅ Si une page s’ouvre

➡ MLU trouvé. Passer à la section **6)**

## ❌ Si rien ne s’ouvre

➡ passez à la section **4)**

---

# 4) Retrouver le MLU SANS installer de logiciel (méthode robuste)

## 4.1 Méthode “arp -a”

Dans `cmd`, tapez :

```bat
arp -a
```



* `http://IP:9994` (une par une pour les IP inconnues)

### Si vous tombez sur une page MLU → aller à **6)**

---

## 4.2 Méthode “PowerShell” (recherche qui répond sur 9994)


### Ouvrir PowerShell

* Menu Windows
* taper : `powershell`
* Entrée

### 4.2.1 D’abord, trouver le réseau du PC

Avec `ipconfig`, si l’IP PC est par ex :

* `192.168.10.25`
  alors le réseau est :
* `192.168.10.X`

### 4.2.2 Lancer ce scan (remplacer 192.168.10 par le bon)

```powershell
1..254 | % { 
  $ip="192.168.10.$_"
  $tcp = New-Object Net.Sockets.TcpClient
  try { 
    $tcp.Connect($ip,9994)
    if($tcp.Connected){ "PORT 9994 OUVERT: $ip" }
  } catch {}
  $tcp.Close()
}
```

### Résultat :

* Si vous voyez `PORT 9994 OUVERT: 192.168.10.XX`
  ➡ ouvrir dans Chrome :
  `http://192.168.10.XX:9994`
  ➡ puis section **6)**

* Si vous ne voyez RIEN
  ➡ passez à la section **5)**

---

# 5) Si aucun scan ne trouve rien : on est dans 3 cas

Quand **TEST MLU OK** mais **aucune IP visible**, il reste 3 possibilités :

## Cas 1 — Le PC n’est pas sur le bon réseau (le plus fréquent)

➡ Solution : **changer temporairement l’IP du PC** pour “se mettre dans le réseau MLU”.

### Comment changer temporairement l’IP (Windows, ultra simple)

1. Appuyer `Windows + R`
2. taper :

```text
ncpa.cpl
```

3. Clic droit sur **Ethernet** → Propriétés
4. Double clic **IPv4**
5. Cocher **Utiliser l’adresse IP suivante**
6. Mettre (exemple réseau maintenance) :

* IP : `192.168.50.20`
* Masque : `255.255.255.0`
* Passerelle : (vide)

7. OK → OK

### Puis tester :

* `ping 192.168.50.10`
* `http://192.168.50.10:9994`

✅ Si ça marche → section **6)**
❌ Si non → retenter avec un autre réseau :

#### Essai réseau WiFi interne :

* IP PC : `192.168.20.20`
* Masque : `255.255.255.0`
  Puis tester `http://192.168.20.10:9994`

#### Essai réseau CMS :

* IP PC : `172.17.13.10`
* Masque : `255.255.0.0`
  Puis tester `http://172.17.30.1:9994`

Si un des 3 marche → section **6)**

---

## Cas 2 — Le MLU n’est pas connecté au réseau avion (câble / port)

➡ Action : **vérifier le câble Ethernet côté MLU**

* Le câble est-il bien branché ?
* Est-ce le bon port ? 

**Astuce simple :**

* quand on branche un câble Ethernet, souvent une petite LED s’allume près du port.
* si aucune LED ne s’allume → câble HS ou mauvais port ou port MLU HS

➡ Si possible : demander au client d’essayer **un autre câble**.

---

## Cas 3 — Port Ethernet du MLU en défaut
Symptôme :

* test MLU OK
* mais **jamais** de ping / jamais de page web / jamais de scan qui détecte

➡ Dans ce cas, la suite logique est :

* soit passer par une **autre interface** (si WiFi interne activable)
* soit intervention sur place / retour matériel

---

# 6) Vous avez trouvé l’IP : que faire pour “refaire fonctionner Clematis” ?

## 6.1 Accès interface MLU

Ouvrir :

* `http://IP_MLU:9994`

### Logins :

* page maintenance : mot de passe **maintenance**
* page installation (HomeInstall) : mot de passe **installation**

> Si le client dit “Submit ne fait rien” :
> essayez Chrome + `Ctrl+Shift+R`, ou Firefox.

---

## 6.2 Identifier ce qui doit être “bon” côté réseau

On compare 4 champs :

* **MLU IP**
* **Subnet mask**
* **Gateway**
* **CMS address**

### Avec quoi comparer ?

➡ Avec les IP du réseau avion (routeur + CMS).

* IP du routeur cabine (souvent la passerelle du PC)
* IP du CMS (si connu)

### Exemple simple

Si le PC (sur réseau avion) est :

* PC = `192.168.10.25`
* Gateway = `192.168.10.1`

Alors le réseau avion est :

* `192.168.10.X`

Donc le MLU doit être un truc comme :

* `192.168.10.50`
  et **CMS address** doit être dans `192.168.10.X` (ex: `192.168.10.2`)

---

## 6.3 Exemple concret “panne IP”

MLU configuré en :

* IP : `10.0.0.20`
* CMS address : `192.168.10.2`

➡ Là Clematis peut “exister” mais **aucune commande n’arrive**.

✅ Correction :

* remettre le MLU en `192.168.10.X`
* vérifier gateway `192.168.10.1`
* garder CMS address sur l’IP CMS réelle

---

## 6.4 Après modification

1. **Save / Apply**
2. **Reboot MLU**

   * soit bouton reboot si dispo
   * soit couper l’alim 30 sec

---

# 7) Valider que CMS ↔ MLU communique 

Ouvrir :

* `http://IP_MLU:9994/HomeInstall.html`

Se connecter (login) : **installation**

Chercher et lancer :

* **Test CMS settings**

### Résultat attendu

 compteurs / statuts qui bougent :

* messages sent / received
* CRC etc.

✅ Si ça bouge → CMS ↔ MLU OK
❌ Si ça bouge pas → problème réseau CMS (MLU ne “voit” pas le CMS)

---

# 8) Valider côté tablette : que faire si Clematis n’apparaît plus ?

## 8.1 D’abord : Wi-Fi

Sur tablette :

* vérifier qu’elle est connectée au **bon Wi-Fi cabine** (SSID)

## 8.2 Ensuite : tester via navigateur

Même si l’app n’apparaît plus, testez :

* `http://IP_MLU:9994`
  ou si un nom DNS existe :
* `http://maintenance:9994`

## 8.3 Si Clematis “disparaît”

C’est souvent :

* tablette pas sur le bon Wi-Fi
* IP du MLU changée (donc l’ancienne URL ne marche plus)
* DNS interne non résolu

➡ Solution : une fois l’IP MLU confirmée, vous donnez au client **l’URL directe**.

---

# 9) Fin de l’intervention : REMETTRE LE PC EN NORMAL

Très important (sinon le client perd internet / réseau avion) :

Retourner sur IPv4 :

* cocher **Obtenir une adresse IP automatiquement**
* OK

---

#  Résumé 
1. TEST MLU OK → c’est réseau/config
2. `ipconfig` → savoir votre réseau
3. tester IP MLU connues
4. `arp -a` puis test `http://IP:9994`
5. PowerShell scan port 9994
6. si toujours rien → changer IP PC (192.168.50.20 puis 192.168.20.20 puis 172.17.13.10)
7. quand IP trouvée → corriger IP/subnet/gateway/CMS address
8. reboot MLU
9. `HomeInstall.html` → Test CMS settings
10. tester Clematis tablette

---
