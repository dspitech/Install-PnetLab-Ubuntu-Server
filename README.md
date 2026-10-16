# PNETLab v6 : installation, durcissement et déploiement d'images Cisco et FortiGate

Guide de référence pour déployer un laboratoire d'émulation réseau PNETLab v6 dans une machine virtuelle Ubuntu Server 20.04, y charger des images Cisco (IOL, Dynamips, QEMU) et Fortinet (FortiGate-VM), puis valider l'ensemble par un lab de test.

| | |
|---|---|
| Plateforme cible | Ubuntu Server 20.04 LTS (Focal), x86_64 |
| Version PNETLab | 6.0.0-103 (paquet principal) |
| Noyau | 5.17.15-pnetlab-uksm-2 |
| Public | Administrateurs systèmes et réseaux, architectes, équipes sécurité |
| Convention | Toutes les commandes sont exécutées en root (`sudo -i`) sauf mention contraire |

> **Statut des informations.** Les versions de paquets et les URL proviennent du script d'origine et doivent être revérifiées avant tout déploiement. Les procédures Fortinet (§12) et Cisco QEMU (§11.3) suivent les conventions de nommage de PNETLab/EVE-NG ; contrôlez-les sur votre version exacte avant de les figer dans une procédure interne.

---

## Sommaire

1. [Périmètre et architecture](#1-périmètre-et-architecture)
2. [Prérequis et dimensionnement](#2-prérequis-et-dimensionnement)
3. [Préparation de l'hyperviseur](#3-préparation-de-lhyperviseur)
4. [Installation d'Ubuntu Server 20.04](#4-installation-dubuntu-server-2004)
5. [Installation de PNETLab](#5-installation-de-pnetlab)
6. [Vérifications post-installation](#6-vérifications-post-installation)
7. [Configuration réseau](#7-configuration-réseau)
8. [Premier accès et modes Online / Offline](#8-premier-accès-et-modes-online--offline)
9. [Durcissement](#9-durcissement)
10. [Gestion des images : arborescence et ishare2](#10-gestion-des-images--arborescence-et-ishare2)
11. [Déploiement des images Cisco](#11-déploiement-des-images-cisco)
12. [Déploiement de FortiGate-VM](#12-déploiement-de-fortigate-vm)
13. [Lab de validation de bout en bout](#13-lab-de-validation-de-bout-en-bout)
14. [Exploitation : sauvegarde, mise à jour, journaux](#14-exploitation--sauvegarde-mise-à-jour-journaux)
15. [Dépannage](#15-dépannage)
16. [Annexes](#16-annexes)
17. [Notes légales](#17-notes-légales)

---

## 1. Périmètre et architecture

### 1.1 Ce que couvre ce document

Installation de PNETLab, configuration réseau, durcissement, import d'images et validation. Les environnements cloud (GCP, Azure) ne sont pas couverts par le script fourni : l'imbrication de virtualisation y dépend du type d'instance et doit être traitée séparément.

### 1.2 Architecture logique

```
                    Réseau d'administration / LAN
                               │
                         ┌─────┴─────┐
                         │  eth0     │   (port de la VM, sans IP)
                         │   │       │
                         │  pnet0 ◄──┼── bridge Linux : porte l'IP de gestion
                         │   │       │   et la "Cloud0" des labs
 Navigateur ── HTTP(S) ─►│ Apache / PHP / MySQL      (interface web)
                         │ Tomcat + Guacamole        (consoles HTML5)
                         │ Docker                    (nœuds conteneurs)
                         │                           │
                         │ ┌───────────────────────┐ │
                         │ │ Nœuds émulés          │ │
                         │ │  IOL  (binaires x86)  │ │
                         │ │  QEMU (KVM) : vIOS,   │ │
                         │ │     CSR, FortiGate... │ │
                         │ │  Dynamips, VPCS       │ │
                         │ └───────────────────────┘ │
                         │   Noyau 5.17.15-pnetlab   │
                         └───────────────────────────┘
                              Hyperviseur (nested)
```

Chaque interface `ethN` de la VM correspond à une `pnetN` (bridge) et à une « Cloud N » dans l'interface web. Un nœud relié à `Cloud0` accède donc au réseau de l'interface `eth0`.

---

## 2. Prérequis et dimensionnement

### 2.1 Prérequis obligatoires

| Élément | Exigence |
|---|---|
| OS invité | Ubuntu Server 20.04, installation propre. Les autres versions sont refusées par le script |
| Architecture | x86_64 |
| Virtualisation | Extensions matérielles (VT-x / AMD-V) exposées à la VM (virtualisation imbriquée) |
| Nom d'hôte | `pnetlab`, à ne jamais modifier ensuite (voir §11.1 : les licences IOL en dépendent) |
| Réseau | Accès Internet pendant l'installation (APT, PPA, labhub.eu.org) |
| Droits | root ou sudo |

### 2.2 Dimensionnement

| Profil | vCPU | RAM | Disque | Usage typique |
|---|---|---|---|---|
| Minimal | 2 | 4 Go | 60 Go | Quelques IOL / VPCS |
| Standard | 4 | 16 Go | 150 Go | Labs CCNA/CCNP, 1 à 2 FortiGate, quelques vIOS |
| Avancé | 8+ | 32 Go et plus | 300 Go et plus (SSD/NVMe) | Topologies sécurité multi-éditeurs |

Ordres de grandeur de consommation par nœud (à ajuster selon la version) :

| Nœud | RAM | Remarque |
|---|---|---|
| VPCS | quasi nulle | Poste virtuel léger |
| IOL L2 / L3 | 256 à 512 Mo | Très économe, idéal pour le routage et la commutation |
| Dynamips (c7200) | 256 à 512 Mo | Dépend de l'IOS |
| vIOS / vIOS-L2 | 512 Mo à 1 Go | QEMU |
| CSR1000v | 3 à 4 Go | QEMU |
| FortiGate-VM | 2 Go | Sans licence payante, limité à 1 vCPU |

---

## 3. Préparation de l'hyperviseur

La VM doit exposer les instructions de virtualisation au système invité.

| Hyperviseur | Réglage |
|---|---|
| VMware Workstation / Fusion | Processors > cocher « Virtualize Intel VT-x/EPT or AMD-V/RVI » |
| VMware ESXi | Option CPU « Expose hardware assisted virtualization to the guest OS ». Placer le port group du réseau en mode promiscuité, modifications d'adresse MAC et transmissions forgées sur « Accept » |
| Proxmox / KVM | Type de CPU `host`, et `nested=1` sur l'hôte (`/sys/module/kvm_intel/parameters/nested` ou `kvm_amd`) |
| VirtualBox | La virtualisation imbriquée n'est disponible que sur certaines combinaisons matériel/version. À éviter pour un usage sérieux (QEMU sans KVM est très lent) |

Configuration recommandée de la VM :

- Contrôleur disque VirtIO ou SCSI, disque en provisionnement fin ou épais selon la politique de stockage.
- Carte réseau : au moins une, en mode bridge ou réseau d'administration. Prévoir des cartes supplémentaires si vous voulez plusieurs Clouds.
- Sur un réseau virtuel d'hyperviseur, autoriser le trafic de MAC multiples (promiscuité), sinon les nœuds émulés n'auront aucune connectivité externe.

---

## 4. Installation d'Ubuntu Server 20.04

### 4.1 Installation

- Choisir « Ubuntu Server (minimized) » ou standard, sans snap supplémentaire.
- Nom d'hôte : `pnetlab`.
- Partitionnement : LVM recommandé (extension aisée du volume).
- Cocher l'installation du serveur OpenSSH.
- Créer un utilisateur d'administration nominatif. Le compte `root` ne sera pas utilisé pour l'accès SSH.

### 4.2 Mise à niveau et contrôles

```bash
sudo -i
apt update && apt full-upgrade -y
hostname                                  # doit afficher : pnetlab
egrep -c '(vmx|svm)' /proc/cpuinfo        # doit être > 0
lsb_release -rs                           # doit afficher : 20.04
```

Si la première commande de contrôle ne renvoie pas `pnetlab` :

```bash
hostnamectl set-hostname pnetlab
```

### 4.3 Snapshot

Prenez un snapshot de la VM à ce stade (état « Ubuntu propre »). Il permet de rejouer l'installation sans réinstaller l'OS.

---

## 5. Installation de PNETLab

### 5.1 Script fourni

Le dépôt contient `scripts/install_pnetlab_v6.sh`, version corrigée du script d'origine.

| Point | Script d'origine | Script fourni |
|---|---|---|
| Gestion des erreurs | Aucune, poursuit après un échec | `set -Eeuo pipefail`, arrêt avec numéro de ligne |
| Verrous dpkg | Supprimés avec `rm /var/lib/dpkg/lock*` (risque de corruption) | Attente de la libération |
| Répertoire de travail | `rm -rf /tmp/*` | Répertoire `mktemp` dédié, supprimé en fin de script |
| Idempotence | Partielle | Test de version avant chaque paquet |
| Traçabilité | Aucune | Journal `/var/log/pnetlab-install.log` et SHA-256 de chaque téléchargement |
| `/etc/hosts` | Test sur `127.0.1.1` mais écriture de `127.0.2.1` (incohérent) | Entrée `127.0.1.1 pnetlab.example.com pnetlab` unique |
| Mot de passe root `pnet` | Imposé | Supprimé (voir §9) |
| `PermitRootLogin yes` | Imposé | Opt-in : `ENABLE_ROOT_SSH=1` |
| Extension LVM | Automatique | Opt-in : `RESIZE_ROOT_LV=1` |
| Blocs GCP / Azure | Inclus | Retirés (hors périmètre) |
| Coquille `$DOwnload` | Présente | Corrigée |

### 5.2 Avertissement sur la chaîne d'approvisionnement

Les paquets `.deb` et le noyau sont téléchargés depuis `labhub.eu.org`, source tierce non officielle, et installés en root. Pour une machine autre qu'un laboratoire isolé :

1. Exécutez l'installation dans une VM dédiée, sans accès aux réseaux de production.
2. Conservez le journal des SHA-256 produit par le script et comparez-le entre déploiements.
3. Faites relire le script et figez un miroir interne des paquets si votre politique l'exige.

### 5.3 Exécution

```bash
sudo -i
mkdir -p /root/pnetlab && cd /root/pnetlab
# copier le script dans ce répertoire (scp, git clone, etc.)
chmod +x install_pnetlab_v6.sh
dos2unix install_pnetlab_v6.sh            # uniquement si créé sous Windows
./install_pnetlab_v6.sh
```

Options :

```bash
RESIZE_ROOT_LV=1 ./install_pnetlab_v6.sh      # étend le LV racine
ENABLE_ROOT_SSH=1 ./install_pnetlab_v6.sh     # déconseillé, voir §9
```

À la fin, **ne redémarrez pas encore** : configurez d'abord le réseau (§7), car le noyau PNETLab et la pile réseau `ifupdown` s'activent au redémarrage.

---

## 6. Vérifications post-installation

Après la configuration réseau du §7 et un redémarrage :

```bash
uname -r                                   # attendu : 5.17.15-pnetlab-uksm-2
lsmod | grep kvm                           # kvm_intel ou kvm_amd chargé
ls -l /dev/kvm                             # le périphérique doit exister
dpkg -l | grep -i pnetlab                  # paquets pnetlab* à l'état ii
systemctl is-active apache2 mysql          # active / active
docker ps 2>&1 | head -3                   # le démon Docker répond
ip -br a                                   # pnet0 porte l'adresse de gestion
```

Si `/dev/kvm` est absent, la virtualisation imbriquée n'est pas exposée (§3) ; les nœuds QEMU ne démarreront pas ou seront inutilisables.

Test d'accès web : depuis un poste du réseau d'administration, ouvrir `http://<IP_pnet0>`.

---

## 7. Configuration réseau

### 7.1 Principe

PNETLab gère son réseau avec `ifupdown` (`/etc/network/interfaces`), pas avec netplan. Le bridge `pnet0` porte l'adresse IP ; `eth0` n'a pas d'IP et sert de port au bridge.

### 7.2 Neutraliser netplan

Ubuntu 20.04 installe une configuration netplan qui entre en conflit. **Travaillez depuis la console de l'hyperviseur, pas en SSH** : vous allez couper la connectivité.

```bash
mkdir -p /root/netplan-backup
mv /etc/netplan/*.yaml /root/netplan-backup/
```

### 7.3 Fichier `/etc/network/interfaces`

IP statique (recommandé pour un serveur de labs) :

```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual

auto pnet0
iface pnet0 inet static
    address 192.168.10.20
    netmask 255.255.255.0
    gateway 192.168.10.1
    dns-nameservers 1.1.1.1 9.9.9.9
    bridge_ports eth0
    bridge_stp off
    bridge_fd 0
```

Variante DHCP : remplacer le bloc `pnet0` par `iface pnet0 inet dhcp` en conservant `bridge_ports eth0`, `bridge_stp off`, `bridge_fd 0`.

Cartes supplémentaires (Cloud1, Cloud2, ...) :

```
auto eth1
iface eth1 inet manual

auto pnet1
iface pnet1 inet manual
    bridge_ports eth1
    bridge_stp off
    bridge_fd 0
```

Appliquer :

```bash
reboot
```

### 7.4 Contrôle

```bash
ip -br a
ping -c2 192.168.10.1                      # passerelle
ping -c2 8.8.8.8                           # IP externe
ping -c2 pnetlab.com                       # résolution DNS
cat /etc/resolv.conf
```

| Résultat | Diagnostic |
|---|---|
| `8.8.8.8` répond mais pas `pnetlab.com` | DNS : corriger `dns-nameservers` |
| Ni l'un ni l'autre ne répond | Passerelle, VLAN ou configuration du port de l'hyperviseur |
| Passerelle injoignable | `bridge_ports` erroné ou carte absente |

### 7.5 Connexion des nœuds au réseau externe

- Un nœud relié à `Cloud0` partage le segment de `eth0`. Il doit donc être adressé dans le LAN d'administration (ou dans un VLAN dédié si le port de l'hyperviseur est en trunk).
- Pour isoler les labs du LAN d'administration, utilisez une seconde carte (`eth1` / `pnet1` / Cloud1) sur un réseau dédié aux labs.
- Si votre version propose un type de réseau NAT, il fournit un accès Internet aux nœuds sans exposer le LAN ; vérifiez sa disponibilité dans le menu d'ajout de réseau.

### 7.6 Cas particulier : machine physique en Wi-Fi

Le Wi-Fi ne peut pas être ponté simplement vers `pnet0`. Dans ce montage, `wlan0` (configuré par netplan) porte l'accès Internet et l'adresse de l'interface web, et les nœuds reliés à `Cloud0` n'ont pas d'accès extérieur sans câble sur `eth0` ou sans NAT. Protégez le fichier netplan (`chmod 600`) car il contient le mot de passe Wi-Fi, et ne le partagez jamais en clair. Cette configuration ne convient pas à un usage de référence ; privilégiez une VM filaire.

---

## 8. Premier accès et modes Online / Offline

### 8.1 Identifiants par défaut

| Accès | Identifiant | Mot de passe par défaut |
|---|---|---|
| Interface web (mode Offline) | `admin` | `pnet` |
| Système (console / SSH) | compte créé à l'installation d'Ubuntu | celui que vous avez défini |

Changez immédiatement le mot de passe `admin` (menu de l'utilisateur dans l'interface web).

### 8.2 Modes

| | Online | Offline |
|---|---|---|
| Internet requis | Oui | Non |
| Compte | Compte PNETLab enregistré (pnetlab.com) | Compte local |
| Labs du Store | Tous | « Open Labs » uniquement |

Le mode actif s'affiche dans le menu System > System Mode.

```bash
mode default offline      # mode proposé par défaut à la connexion : offline
mode default online
mode reset offline        # réinitialise le mot de passe du compte offline
mode reset all            # remise à zéro des modes
```

Si l'interface affiche « OFFLINE Mode is disabled », connectez-vous une première fois en mode Online, puis activez-le dans System > System Mode.

### 8.3 Client pack

Pour ouvrir les consoles dans des clients natifs (telnet via PuTTY, VNC, Wireshark), installez le client pack sur le poste de travail. La console HTML5 (Guacamole) fonctionne sans aucune installation.

---

## 9. Durcissement

PNETLab est conçu pour un laboratoire ; il n'a pas vocation à être exposé sur Internet.

| Mesure | Commande / action |
|---|---|
| Aucun mot de passe par défaut | Changer `admin` / `pnet` et ne pas conserver de mot de passe système faible |
| SSH par clés, sans root | `PermitRootLogin no` et `PasswordAuthentication no` dans `/etc/ssh/sshd_config`, puis `systemctl restart ssh` |
| Segmentation | Placer l'interface de gestion dans un VLAN d'administration, les labs sur un réseau dédié (Cloud1) |
| Pare-feu hôte | Ouvrir uniquement SSH et HTTP(S) depuis les postes d'administration (exemple ci-dessous) |
| HTTPS | Mettre un reverse proxy ou un certificat sur Apache si la machine est partagée |
| Sauvegardes | Voir §14 |
| Pas de secrets dans les configurations | Ne jamais versionner de `iourc`, de fichier netplan Wi-Fi ou de configuration d'équipement contenant des clés |

Exemple `ufw` (à valider avant d'activer, depuis la console de l'hyperviseur) :

```bash
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow from 192.168.10.0/24 to any port 22 proto tcp
ufw allow from 192.168.10.0/24 to any port 80 proto tcp
ufw allow from 192.168.10.0/24 to any port 443 proto tcp
# Consoles natives (telnet/VNC) : à n'ouvrir que si le client pack est utilisé.
# Vérifier les plages exactes avec : ss -tlnp | grep -E 'qemu|iol|dynamips'
ufw enable
```

> Testez le comportement de `ufw` avec vos labs : selon la configuration de `br_netfilter`, les règles peuvent aussi s'appliquer au trafic ponté entre nœuds.

---

## 10. Gestion des images : arborescence et ishare2

### 10.1 Arborescence

| Type de nœud | Répertoire |
|---|---|
| IOL (binaires Cisco x86) | `/opt/unetlab/addons/iol/bin/` |
| Dynamips (IOS 7200, etc.) | `/opt/unetlab/addons/dynamips/` |
| QEMU (vIOS, CSR, FortiGate, ASAv...) | `/opt/unetlab/addons/qemu/<préfixe>-<nom>/` |
| Docker | Géré par `docker` (images locales) |

### 10.2 Règle impérative : corriger les permissions

Après **chaque** ajout d'image, quelle que soit la méthode :

```bash
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions
```

Sans cela, l'image n'est pas reconnue ou le nœud s'éteint immédiatement.

### 10.3 Installation d'ishare2

`ishare2` est un outil en ligne de commande pour rechercher et récupérer des images communautaires. Utilisez le dépôt `ishare2-org/ishare2-cli` (l'ancien dépôt `pnetlabrepo/ishare2` n'est plus maintenu).

```bash
apt install -y git
git clone https://github.com/ishare2-org/ishare2-cli.git
mkdir -p /opt/ishare2/cli
cp -r ishare2-cli/* /opt/ishare2/cli/
cp /opt/ishare2/cli/ishare2 /usr/sbin/ishare2
chmod +x /usr/sbin/ishare2
ishare2                                    # première exécution : initialisation
which ishare2
```

Le projet propose aussi une installation en une ligne (`curl ... | sh`). Comme pour tout script distant, lisez-le avant exécution.

### 10.4 Commandes

| Commande | Fonction |
|---|---|
| `ishare2 test` | Vérifie l'accès aux dépôts |
| `ishare2 search bin` | Liste les images IOL |
| `ishare2 search qemu` | Liste les images QEMU |
| `ishare2 search dynamips` | Liste les images Dynamips |
| `ishare2 search all` | Liste tout |
| `ishare2 pull bin <n°>` | Télécharge l'image IOL portant ce numéro |
| `ishare2 pull qemu <n°>` | Télécharge une image QEMU |
| `ishare2 pull dynamips <n°>` | Télécharge une image Dynamips |
| `ishare2 installed bin` | Liste les images IOL installées |
| `ishare2 upgrade` | Met à jour ishare2 |

Filtrer par type d'IOL :

```bash
ishare2 search bin | grep -i l3     # routeurs
ishare2 search bin | grep -i l2     # commutateurs
```

Remarques :

- `ishare2 upgrade` peut proposer des mises à jour de PNETLab. N'acceptez pas sur une installation faite par script sans avoir pris un snapshot.
- L'interface web d'ishare2 (`ishare2 gui install`) est signalée comme instable par ses auteurs ; elle s'exécute en root.
- En mode Offline de PNETLab, ishare2 reste dépendant d'Internet. Téléchargez en amont ou transférez par SCP/WinSCP, puis exécutez `fixpermissions`.
- En cas d'erreur `Failed to download the JSON index file`, le problème est presque toujours DNS ou pare-feu : reprenez le §7.4.

---

## 11. Déploiement des images Cisco

### 11.1 IOL (IOS on Linux)

Les images IOL sont des binaires 32 bits très légers, adaptés au routage et à la commutation.

**Bibliothèques 32 bits** (le script les installe, à vérifier) :

```bash
dpkg --add-architecture i386
apt update
apt install -y libc6:i386 zlib1g:i386
ldd /opt/unetlab/addons/iol/bin/<IMAGE>.bin       # aucune ligne "not found"
```

**Dépôt de l'image** :

```bash
cp <IMAGE>.bin /opt/unetlab/addons/iol/bin/
chmod +x /opt/unetlab/addons/iol/bin/<IMAGE>.bin
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions
```

**Licence.** Les images IOL exigent un fichier `/opt/unetlab/addons/iol/bin/iourc`, au format :

```
[license]
pnetlab = <clé de licence>;
```

La clé est liée au nom d'hôte de la machine (`pnetlab`) : c'est la raison pour laquelle le nom d'hôte ne doit pas changer, notamment après clonage de la VM. Ce document ne décrit aucune méthode de génération de licence : l'utilisation d'IOL suppose que vous disposez des droits Cisco correspondants. L'alternative officielle est Cisco Modeling Labs (CML).

**Choix du template.**

| Image | Fonction | Template PNETLab |
|---|---|---|
| L3 (`...-l3-...`) | Routage | « Cisco IOL » |
| L2 (`...-l2-...`) | Commutation | « Cisco IOL L2 » |

Ne mélangez pas les deux : un template L3 avec une image L2 (ou inversement) provoque des arrêts au démarrage.

**Création du nœud.** Dans un lab : clic droit > Add an object > Node > Cisco IOL. Sélectionner l'image, ajuster RAM (256 Mo en général), nombre de groupes d'interfaces Ethernet / série, puis démarrer.

### 11.2 Dynamips

Pour les routeurs 7200 et plateformes anciennes :

```bash
cp c7200-adventerprisek9-mz.<version>.image /opt/unetlab/addons/dynamips/
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions
```

L'IOS doit être au format décompressé accepté par Dynamips. Utilisez le template « Dynamips » (c7200 ou autre) et, si l'interface le demande, ajustez l'idle-PC pour limiter la charge CPU.

### 11.3 Images QEMU Cisco (vIOS, CSR1000v, ASAv, Nexus)

Convention : un répertoire par version, dont le préfixe détermine le template, et un disque nommé selon l'interface émulée.

| Équipement | Préfixe de répertoire (exemple) | Nom du disque |
|---|---|---|
| vIOS (routeur) | `vios-adventerprisek9-m.SPA.<version>` | `hda.qcow2` |
| vIOS-L2 (commutateur) | `viosl2-adventerprisek9-m.<version>` | `hda.qcow2` |
| CSR1000v | `csr1000vng-universalk9.<version>` | `virtioa.qcow2` |
| ASAv | `asav-<version>` | `hda.qcow2` |

Procédure générique :

```bash
mkdir -p /opt/unetlab/addons/qemu/vios-adventerprisek9-m.SPA.159-3.M6
cd /opt/unetlab/addons/qemu/vios-adventerprisek9-m.SPA.159-3.M6
# placer ici l'image disque (qcow2) sous le nom attendu
mv /chemin/source.qcow2 hda.qcow2
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions
```

Si l'image est fournie dans un autre format (VMDK, OVA, ISO), convertissez-la :

```bash
qemu-img convert -f vmdk -O qcow2 source.vmdk hda.qcow2
```

Contrôlez le nom de disque et les paramètres exacts de chaque template dans l'interface (menu d'ajout de nœud, onglet de description du template) : ils varient selon la plateforme (par exemple `virtioa.qcow2`, `sataa.qcow2`).

---

## 12. Déploiement de FortiGate-VM

### 12.1 Obtention de l'image

1. Créer un compte sur le portail support Fortinet (FortiCloud).
2. Télécharger le firmware **FortiGate-VM pour KVM** (archive nommée du type `FGT_VM64_KVM-v<version>-build<xxxx>-FORTINET.out.kvm.zip`).
3. Extraire l'archive : elle contient `fortios.qcow2`.

L'image doit provenir du portail officiel. Ne téléchargez pas de firmware Fortinet depuis des sources tierces : un firmware réseau compromis est un risque majeur de sécurité.

### 12.2 Dépôt dans PNETLab

Le préfixe `fortinet-` active le template Fortinet ; le disque doit s'appeler `virtioa.qcow2`.

```bash
VER="v7.2.8-build1639"      # adapter à la version téléchargée
mkdir -p /opt/unetlab/addons/qemu/fortinet-FGT-${VER}
cp fortios.qcow2 /opt/unetlab/addons/qemu/fortinet-FGT-${VER}/virtioa.qcow2
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions
```

Vérification :

```bash
ls -l /opt/unetlab/addons/qemu/fortinet-FGT-${VER}/
```

Le fichier `virtioa.qcow2` doit être présent, avec les droits positionnés par `fixpermissions`.

### 12.3 Création du nœud

Dans un lab : Add an object > Node > Fortinet FortiGate. Paramètres recommandés :

| Paramètre | Valeur |
|---|---|
| Image | `fortinet-FGT-<version>` |
| CPU | 1 (une licence d'évaluation ou absente limite le nombre de vCPU) |
| RAM | 2048 Mo (ne pas descendre en dessous de ce que demande la version) |
| Ethernet | 4 à 8 ports |
| Console | telnet ou HTML5 |

### 12.4 Premier démarrage

1. Démarrer le nœud et ouvrir la console. Le démarrage prend plusieurs minutes.
2. Connexion initiale : utilisateur `admin`, mot de passe vide. Le système impose la définition d'un nouveau mot de passe.
3. Configurer l'interface de gestion (connectée à `Cloud0` ou à un autre réseau du lab) :

```
config system interface
    edit "port1"
        set mode static
        set ip 192.168.10.50 255.255.255.0
        set allowaccess ping https ssh
    next
end
config router static
    edit 1
        set gateway 192.168.10.1
        set device "port1"
    next
end
config system dns
    set primary 1.1.1.1
    set secondary 9.9.9.9
end
```

4. Accéder à l'interface web : `https://192.168.10.50` depuis le poste d'administration.

Pour un durcissement dès la première minute : restreindre `allowaccess` aux protocoles nécessaires, définir des `trusthost` pour l'administrateur, et ne laisser aucun accès HTTP non chiffré.

### 12.5 Licence

| Situation | Effet |
|---|---|
| Sans licence | Le système démarre avec un fonctionnement très restreint. Une activation est requise pour une utilisation réelle |
| Licence d'évaluation (compte FortiCloud) | Fonctionnalités limitées : 1 vCPU, RAM plafonnée, nombre d'interfaces et de fonctions réduit |
| Licence achetée | Capacités selon le contrat |

La politique d'évaluation de Fortinet évolue selon les versions de FortiOS (durée, activation par connexion FortiCloud depuis l'interface, ouverture de ports sortants vers FortiGuard). Consultez la documentation Fortinet de votre version. Si l'activation passe par Internet, donnez un accès sortant au nœud (NAT ou Cloud0 avec passerelle).

### 12.6 Points d'attention

- Les performances d'un FortiGate émulé en lab ne sont pas représentatives de la production : ne dimensionnez pas d'après un lab.
- Certaines versions récentes exigent plus de RAM ou un format de disque particulier. Si le nœud boucle au démarrage, consultez la console série et les notes de version.
- Une topologie de test avec plusieurs FortiGate (HA, IPsec site à site) demande de la RAM supplémentaire : prévoir 2 Go par instance.
- FortiManager et FortiAnalyzer suivent la même procédure, avec des images et des ressources beaucoup plus volumineuses (plusieurs vCPU, 8 Go et plus).

---

## 13. Lab de validation de bout en bout

Ce lab valide la chaîne complète : PNETLab, réseau, IOL et FortiGate.

### 13.1 Topologie

```
 [R1 IOL L3] ──── [FortiGate port2]      FortiGate port1 ──── [Cloud0]
   10.0.0.1/24         10.0.0.2/24                              (LAN / Internet)
      │
 [SW1 IOL L2] ──── [VPCS1 192.168.1.10]
```

### 13.2 Étapes

1. Créer un lab : New > Lab.
2. Ajouter R1 (Cisco IOL L3), SW1 (Cisco IOL L2), VPCS1, un FortiGate et un réseau Cloud0.
3. Câbler comme sur le schéma, puis démarrer tous les nœuds.
4. Configuration de R1 :

```
enable
configure terminal
 hostname R1
 interface Ethernet0/0
  ip address 10.0.0.1 255.255.255.0
  no shutdown
 interface Ethernet0/1
  ip address 192.168.1.1 255.255.255.0
  no shutdown
 ip route 0.0.0.0 0.0.0.0 10.0.0.2
end
write memory
```

5. Configuration du FortiGate : `port2` en `10.0.0.2/24`, route vers `192.168.1.0/24` via `10.0.0.1`, et une politique firewall autorisant `port2` vers `port1` (avec NAT).
6. Sur VPCS1 :

```
ip 192.168.1.10/24 192.168.1.1
ping 10.0.0.2
ping 192.168.10.1
```

### 13.3 Critères de réussite

| Test | Résultat attendu |
|---|---|
| `ping 10.0.0.2` depuis VPCS1 | Réponses |
| Accès à l'interface web du FortiGate | Page de connexion HTTPS |
| `show ip route` sur R1 | Route par défaut présente |
| Redémarrage du lab | Les nœuds repartent sans erreur |

---

## 14. Exploitation : sauvegarde, mise à jour, journaux

### 14.1 Sauvegarde

| Élément | Chemin | Fréquence |
|---|---|---|
| Labs et projets | `/opt/unetlab/labs/` | À chaque modification importante |
| Base de données | `mysqldump --all-databases > /root/pnet-db.sql` | Quotidien |
| Images | `/opt/unetlab/addons/` | Après chaque import (volumineux) |
| Réseau | `/etc/network/interfaces` | À chaque changement |
| Snapshot VM | Hyperviseur | Avant toute mise à jour |

Exemple :

```bash
tar czf /root/pnet-labs-$(date +%F).tgz /opt/unetlab/labs
mysqldump --all-databases > /root/pnet-db-$(date +%F).sql
```

Stockez ces sauvegardes hors de la VM.

### 14.2 Mise à jour

Aucune mise à jour automatique n'est recommandée : prenez un snapshot, vérifiez la compatibilité avec la version d'Ubuntu et l'état des paquets, puis testez sur une copie. Évitez `ishare2 upgrade` pour PNETLab lui-même sur une installation par script.

### 14.3 Journaux

```bash
tail -n 50 /opt/unetlab/data/Logs/unl_wrapper.txt
tail -n 50 /var/log/pnetlab-install.log
journalctl -u apache2 --since "1 hour ago"
```

---

## 15. Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| « Ubuntu 20.04 requis » | Mauvaise version d'OS | Réinstaller en 20.04 |
| `bad interpreter` | Fins de ligne Windows | `dos2unix install_pnetlab_v6.sh` |
| Attente prolongée du verrou dpkg | `unattended-upgrades` actif | Laisser terminer ou `systemctl stop unattended-upgrades` |
| Virtualisation matérielle absente | Imbrication non exposée | Reprendre le §3 |
| Pas d'accès web | Réseau mal configuré | §7.4, puis `systemctl status apache2` |
| Nœuds QEMU qui ne démarrent pas | `/dev/kvm` absent | §3 |
| Image invisible ou nœud qui s'éteint immédiatement | Permissions | `fixpermissions` |
| IOL : `not found` avec `ldd` | Bibliothèques 32 bits | §11.1 |
| IOL : `invalid license` | `iourc` absent, invalide ou nom d'hôte modifié | Contrôler `iourc` et `hostname` |
| `Segmentation fault` | Image corrompue ou RAM insuffisante | Retélécharger, vérifier `free -m` |
| `unable to open NETMAP` | Message normal en lancement manuel | Aucune action |
| FortiGate bloqué au démarrage | RAM ou version incompatible | Console série, augmenter la RAM, consulter les notes de version |
| FortiGate : disque non trouvé | Mauvais nom de fichier | Le disque doit s'appeler `virtioa.qcow2` |
| Nœud sans accès externe | Cloud non relié à une interface active, promiscuité refusée | §3 et §7.5 |
| `Failed to download the JSON index file` | DNS ou pare-feu | §7.4 |

Test manuel d'une image IOL pour lire l'erreur réelle :

```bash
cd /opt/unetlab/addons/iol/bin
export IOURC=/opt/unetlab/addons/iol/bin/iourc
./<IMAGE>.bin 1
```

Autres contrôles :

```bash
ps aux | grep -E 'i86bi|qemu'
free -m
df -h /opt
```

---

## 16. Annexes

### 16.1 Bonnes pratiques

1. Snapshot de la VM une fois le système stable.
2. Ne jamais renommer l'hôte `pnetlab`.
3. Lancer `fixpermissions` après chaque ajout d'image.
4. Ne pas mélanger les templates L2 et L3.
5. Changer tous les mots de passe par défaut.
6. Ne jamais publier de fichier contenant un mot de passe, une clé ou une licence.
7. Documenter les versions d'images utilisées dans chaque lab.

### 16.2 Commandes utiles

```bash
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions
ishare2 test
ishare2 search all
ishare2 installed bin
mode default offline
```

### 16.3 Récapitulatif des chemins

| Objet | Chemin |
|---|---|
| IOL | `/opt/unetlab/addons/iol/bin/` |
| Licence IOL | `/opt/unetlab/addons/iol/bin/iourc` |
| Dynamips | `/opt/unetlab/addons/dynamips/` |
| QEMU | `/opt/unetlab/addons/qemu/<préfixe>-<nom>/` |
| Labs | `/opt/unetlab/labs/` |
| Journaux du wrapper | `/opt/unetlab/data/Logs/unl_wrapper.txt` |
| Journal d'installation | `/var/log/pnetlab-install.log` |
| Configuration réseau | `/etc/network/interfaces` |

---

## 17. Notes légales

- Les images Cisco (IOL, IOS, vIOS, CSR, ASAv) et Fortinet (FortiOS) sont la propriété de leurs éditeurs. Il vous appartient de disposer des licences nécessaires. Ce document ne décrit pas de méthode pour contourner ou générer des licences.
- Les alternatives officielles : Cisco Modeling Labs (CML) pour Cisco, et les licences d'évaluation ou de laboratoire de Fortinet.
- Les paquets d'installation de PNETLab proviennent de sources tierces : vérifiez leur provenance avant tout usage hors laboratoire.
