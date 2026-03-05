

test mlu ok 
probleme reseau 


1️⃣ Contexte
Quand le problème a commencé ?
Qu’est-ce qui a été modifié ?
IP modifiées ?

2️⃣ Symptômes
Clematis visible ?
Couleurs changent ?
Réaction des lampes ?


3️⃣ Mode TEST
Bouton TEST MLU ?
Couleurs changent ?



➡ si oui

MLU OK
LMCU OK


4️⃣ Accès réseau
IP actuelle du MLU ?
URL utilisée ?
maintenance:9994 ?


5️⃣ Réseau cabine
IP CMS ?
IP routeur WiFi ?
Subnet ?


6️⃣ Tablette
WiFi connecté ?
Nom du réseau ?
Clematis app ou web ?


7️⃣ Configuration modifiée
IP MLU ?
Gateway ?
Subnet ?
CMS address ?


8️⃣ Matériel
MLU remplacé ?
Routeur changé ?
LMCU combien ?



1️⃣ Context
When did the problem start?
What was modified?
Modified IPs?

2️⃣ Symptoms
Clematis visible?
Colors changing?
Lamp reaction?

3️⃣ TEST mode
MLU TEST button?
Colors changing?

➡ if yes

MLU OK
LMCU OK

4️⃣ Network access
Current IP of MLU?
URL used?
maintenance:9994?

5️⃣ Cabin network
CMS IP?
WiFi router IP?
Subnet?

6️⃣ Tablet
WiFi connected?
Network name?
Clematis app or web?

7️⃣ Modified configuration
MLU IP?
Gateway?
Subnet?
CMS address?

8️⃣ Hardware
MLU replaced?
Router changed?
How many LMCUs?
#  GUIDE SUPPORT MLU / CLEM — ARBRE DE DIAGNOSTIC

Utiliser **dans cet ordre**.

---

# 1️ Vérifier alimentation MLU

### Question client

> Le MLU est-il alimenté en 28V ?

### Si NON

Action :

* vérifier alimentation
* vérifier fusible
* vérifier connecteur J1

Puis :

➡ redémarrer MLU
➡ reprendre diagnostic

---

### Si OUI

Passer à :

➡ **Étape 2**

---

# 2️ Vérifier LED CR10

### Question

> Quelle est la couleur de la LED CR10 ?

---

## 🟢 Réponse : VERT FIXE

Signification :

```text
MLU démarré correctement
```

Action :

➡ passer au diagnostic **réseau**

---

## 🔴 Réponse : ROUGE FIXE

Signification probable :

```text
erreur hardware
firmware crash
```

Action :

1️ redémarrer MLU
2️ attendre 45 secondes

Si toujours rouge :

➡ suspect **firmware ou hardware**

---

## 🔴🟢 Réponse : CLIGNOTE ROUGE/VERT

Signification :

```text
erreur détectée pendant self test
```

Action :

Demander au client :

 appuyer sur bouton **TEST**

Si LED devient verte :

➡ erreur temporaire
➡ continuer diagnostic

---

# 3️ Vérifier connexion Ethernet

### Question

> Le PC est-il connecté sur le port Ethernet 2 du MLU ?

---

##  NON

Action :

➡ brancher sur **Ethernet 2**

Puis :

➡ refaire test connexion

---

##  OUI

Passer à :

➡ **Test IP**

---

# 4️ Vérifier IP du PC

Demander au client :

```bash
ipconfig
```

---

### Cas 1 — IP correcte

Exemple :

```
192.168.50.20
```

Action :

➡ passer au **ping**

---

### Cas 2 — IP incorrecte

Exemple :

```
192.168.1.X
10.X.X.X
```

Action :

Configurer :

```
IP : 192.168.50.20
Masque : 255.255.255.0
```
Voici **exactement comment faire sous Windows**, étape par étape, pour configurer :

```
IP : 192.168.50.20
Masque : 255.255.255.0
```

C’est **la configuration nécessaire pour communiquer avec le MLU via l’interface maintenance**. 

---

#  Procédure Windows (à faire avec le client)

## 1️ Ouvrir les paramètres réseau

Demandez au client :

```
Appuyer sur la touche Windows
taper : Panneau de configuration
```

Puis :

```
Réseau et Internet
```

---

## 2️ Ouvrir les connexions réseau

Cliquer sur :

```
Centre Réseau et partage
```

Puis :

```
Modifier les paramètres de la carte
```

Vous allez voir les cartes réseau.

---

## 3️ Choisir la carte Ethernet

Faire **clic droit** sur :

```
Ethernet
```

Puis :

```
Propriétés
```

---

## 4️ Ouvrir IPv4

Dans la liste :

```
Internet Protocol Version 4 (TCP/IPv4)
```

Puis cliquer :

```
Propriétés
```

---

## 5️ Entrer les paramètres

Cocher :

```
Utiliser l'adresse IP suivante
```

Puis entrer :

```
Adresse IP : 192.168.50.20
Masque : 255.255.255.0
Passerelle : laisser vide
```

DNS :

```
laisser vide
```

---

## 6️ Valider

Cliquer :

```
OK
OK
Fermer
```

---

#  Vérification

Demander au client d’ouvrir :

```
Invite de commande
```

Puis taper :

```
ipconfig
```

Vous devez voir :

```
IPv4 : 192.168.50.20
```

---

#  Test communication avec le MLU

Toujours dans l’invite de commande :

```
ping 192.168.50.10
```

---

## Résultat attendu

```
Reply from 192.168.50.10
```

Cela signifie :

```
PC ↔ MLU connecté
```

---

#  Accès interface maintenance

Dans navigateur :

```
http://192.168.50.10:9994
```

login :

```
maintenance
```




Puis :

➡ refaire test

---

# 5️ Tester communication réseau

Demander :

```bash
ping 192.168.50.10
```

---

## ✔ Réponse reçue

Exemple :

```
Reply from 192.168.50.10
```

Signification :

```
connexion PC ↔ MLU OK
```

Action :

➡ tester interface web
http://IP:9994/HomeInstall.html
---

##  Timeout

Signification possible :

```
mauvais câble
mauvais port
MLU bloqué
```

Action :

1️ changer câble Ethernet
2️ redémarrer MLU
3️ vérifier port Ethernet

Si toujours timeout :

➡ suspect **carte réseau MLU**

---

# 6️ Accéder interface web

Navigateur :

```
http://192.168.50.10:9994
```

---

##  Page s'ouvre

Action :

➡ passer au **test CMS**

---

##  Page ne s'ouvre pas

Action :

tester :

```
http://172.17.30.1:9994
```

Si marche :

➡ client connecté sur **interface CMS**

Sinon :

➡ redémarrer MLU

---

# 7️ Test communication CMS

Page :

```
Test CMS settings
```

Observer :

```
messages envoyés
messages reçus
```

---

##  Messages présents

Signification :

```
CMS ↔ MLU OK
```

Action :

➡ tester **LMCU**

---

##  Aucun message

Signification :

```
CMS non connecté
```

Action :

1️ vérifier câble CMS

2️ vérifier réseau CMS

3️ vérifier IP CMS

---

# 8️ Test LMCU

Appuyer bouton :

```
TEST
```

Observer lampes.

---

##  Les couleurs changent

Exemple :

```
rouge
bleu
vert
blanc
```

Signification :

```
LMCU OK
lampes OK
```

Problème probable :

```
logiciel CLEM
```

---

##  Lampes clignotent 3 fois rouge

Signification :

```
LMCU non détecté
```

Action :

1️⃣ vérifier câble RS485
2️⃣ vérifier alimentation LMCU
3️⃣ vérifier connecteur J4

---

##  Lampes clignotent 2 fois rouge

Signification :

```
LMCU mal programmé
```

Action :

➡ reprogrammer LMCU via interface

---

# 9️ Si tout fonctionne mais CLEM ne marche pas

Cause probable :

```
bug logiciel
configuration
```

Action :

1️⃣ redémarrer CLEM
2️⃣ reconnecter MLU
3️⃣ recharger scénario

---



