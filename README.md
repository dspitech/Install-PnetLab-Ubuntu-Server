# Installation de PNETLab v6, de ishare2 et des images IOL

Ce document décrit la procédure complète pour installer PNETLab v6 sur Ubuntu Server 20.04 à l'aide d'un script d'installation, puis pour récupérer des images avec l'outil ishare2, corriger les problèmes courants et configurer le réseau. Toutes les commandes se lancent en root.

## Sommaire

1. Prérequis
2. Création du script d'installation
3. Attribution des autorisations
4. Contenu du script
5. Exécution du script
6. Configuration après installation
7. Installation et utilisation d'ishare2
8. Emplacement des images et permissions
9. Mode Offline de PNETLab
10. Identifiants par défaut
11. Dépannage
12. Bonnes pratiques
13. Avertissement et note légale

## 1. Prérequis

| Élément | Détail |
|---|---|
| Système d'exploitation | Ubuntu Server 20.04 (Focal Fossa), installation propre recommandée |
| Privilèges | Accès root ou utilisateur disposant de sudo |
| Connexion | Accès Internet stable (téléchargement de paquets et de dépôts externes) |
| Mémoire vive | 4 Go minimum pour un usage léger, davantage pour des topologies importantes |
| Virtualisation | Virtualisation imbriquée activée si PNETLab est exécuté dans une machine virtuelle (VMware, VirtualBox) |
| Nom d'hôte | `pnetlab`, à ne pas modifier après l'installation |

Le script vérifie la version d'Ubuntu et s'arrête si elle n'est pas la 20.04. Les versions plus récentes ne sont pas prises en charge par cette procédure.

Pour vérifier le nom d'hôte :

```bash
hostname
```

La commande doit afficher `pnetlab`.

## 2. Création du script d'installation

Connectez-vous en root ou passez en root :

```bash
sudo -i
```

Créez le fichier `install_pnetlab_V6.sh` avec l'éditeur de votre choix :

```bash
nano install_pnetlab_V6.sh
```

Collez le contenu fourni à la section 4, puis enregistrez (Ctrl+O, Entrée) et quittez (Ctrl+X).

## 3. Attribution des autorisations

Rendez le script exécutable :

```bash
chmod +x install_pnetlab_V6.sh
```

Si le fichier a été créé depuis un système Windows, convertissez les fins de ligne pour éviter les erreurs d'interprétation :

```bash
dos2unix install_pnetlab_V6.sh
```

## 4. Contenu du script

Le script ci-dessous réalise uniquement l'installation de PNETLab v6. Il est organisé en 14 sections, chacune introduite par un bandeau de commentaires décrivant son rôle. L'outil ishare2 n'en fait pas partie : il s'installe après le redémarrage (section 7).

```bash
#!/bin/bash
# =============================================================================
# Script      : install_pnetlab_V6.sh
# Objet       : Installation et mise à niveau de PNETLab v6 (et de ses
#               dépendances) sur Ubuntu 20.04.
# Prérequis   : Ubuntu 20.04 (Focal), exécution en root, accès Internet.
# Utilisation : chmod +x install_pnetlab_V6.sh && ./install_pnetlab_V6.sh
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION 1 : INITIALISATION DE L'ENVIRONNEMENT
# -----------------------------------------------------------------------------
clear                                   # Nettoie le terminal avant l'exécution
export LC_ALL=C                         # Force la locale neutre pour un comportement prévisible des commandes
export DEBIAN_FRONTEND=noninteractive   # Empêche apt/dpkg de poser des questions interactives

# Script designed to upgrade dependencies in PNETLab UBUNTU 20.04
# Requirement: You need to have UBUNTU 20.04

# -----------------------------------------------------------------------------
# SECTION 2 : CONSTANTES ET VARIABLES
# -----------------------------------------------------------------------------
# Codes de couleur ANSI utilisés pour l'affichage des messages
GREEN='\033[32m'      # Messages de progression et de réussite
RED='\033[31m'        # Messages d'erreur
NO_COLOR='\033[0m'    # Réinitialisation de la couleur

# Nom de l'archive contenant le noyau PNETLab
KERNEL=pnetlab_kernel.zip

# Suppression d'éventuels verrous dpkg résiduels, puis reconfiguration des
# paquets dont l'installation aurait été interrompue lors d'une exécution précédente
rm /var/lib/dpkg/lock* &>/dev/null
dpkg --configure -a &>/dev/null

# URL de téléchargement des composants PNETLab (dépôt labhub.eu.org)
URL_KERNEL=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/L/linux-5.17.15-pnetlab-uksm/pnetlab_kernel.zip            # Noyau Linux 5.17.15 optimisé PNETLab
URL_PRE_DOCKER=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/D/pre-docker.zip                                        # Prérequis Docker
URL_PNET_GUACAMOLE=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/P/PNET_GUACAMOLE/pnetlab-guacamole_6.0.0-7_amd64.deb   # Accès console via navigateur (Guacamole)
URL_PNET_DYNAMIPS=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/P/PNET_DYNAMIPS/pnetlab-dynamips_6.0.0-30_amd64.deb    # Émulateur de routeurs Cisco (Dynamips)
URL_PNET_SCHEMA=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/P/PNET_SCHEMA/pnetlab-schema_6.0.0-30_amd64.deb          # Schéma de base de données
URL_PNET_VPC=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/P/PNET_VPC/pnetlab-vpcs_6.0.0-30_amd64.deb                  # Postes virtuels légers (VPCS)
URL_PNET_QEMU=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/P/PNET_QEMU/pnetlab-qemu_6.0.0-30_amd64.deb                # Émulateur QEMU
URL_PNET_DOCKER=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/P/PNET_DOCKER/pnetlab-docker_6.0.0-30_amd64.deb          # Gestion des conteneurs Docker
URL_PNET_PNETLAB=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/P/PNET_PNETLAB/pnetlab_6.0.0-103_amd64.deb              # Paquet principal PNETLab
URL_PNET_WIRESHARK=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/P/PNET_WIRESHARK/pnetlab-wireshark_6.0.0-30_amd64.deb # Capture de trames avec Wireshark
URL_PNET_TPM=https://labhub.eu.org/0:/pnetlab/upgrades_pnetlab/focal/T/swtpm-focal.zip                                          # Module TPM logiciel (swtpm)

# -----------------------------------------------------------------------------
# SECTION 3 : VÉRIFICATION DE LA VERSION D'UBUNTU
# Le script est conçu uniquement pour Ubuntu 20.04 : il s'arrête dans le cas contraire
# -----------------------------------------------------------------------------
lsb_release -r -s | grep -q 20.04
if [ $? -ne 0 ]; then
    echo -e "${RED}Upgrade has been rejected. You need to have UBUNTU 20.04 to use this script${NO_COLOR}"
    exit 0
fi

# -----------------------------------------------------------------------------
# SECTION 4 : FONCTION SPÉCIFIQUE À MICROSOFT AZURE
# Si un disque de données (sdc) est attaché, il est partitionné, formaté en
# ext4, monté sur /opt et déclaré dans /etc/fstab pour un montage persistant
# -----------------------------------------------------------------------------
# On Azure attach data disk
azure_disk_tune() {
    ls -l /dev/disk/by-id/ | grep -q sdc && (
        echo o # Create a new empty DOS partition table
        echo n # Add a new partition
        echo p # Primary partition
        echo 1 # Partition number
        echo   # First sector (Accept default: 1)
        echo   # Last sector (Accept default: varies)
        echo w # Write changes
    ) | sudo fdisk /dev/sdc && (
        mke2fs -F /dev/sdc1
        echo "/dev/sdc1	/opt	ext4	defaults,discard	0 0 " >>/etc/fstab
        mount /opt
    )
}

# Appel de la fonction uniquement si le noyau détecté est de type Azure
uname -a | grep -q -- "-azure " && azure_disk_tune

# -----------------------------------------------------------------------------
# SECTION 5 : CONFIGURATION SYSTÈME DE BASE
# -----------------------------------------------------------------------------
# Mise à jour de l'index des paquets
apt-get update

# Autorise la connexion SSH en root et réduit le délai d'arrêt des services à 5 secondes
#permit root access from ssh
sed -i -e "s/.*PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config &>/dev/null
sed -i -e 's/.*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf &>/dev/null
systemctl restart ssh &>/dev/null

# Ajout du dépôt PPA fournissant PHP 7.4 (version requise par PNETLab)
#install  packages required
add-apt-repository --yes ppa:ondrej/php &>/dev/null

# Définit le mot de passe root par défaut ("pnet") lors d'une première installation uniquement
# set passwrod for root
if [ ! -e /opt/ovf/.configured ]; then
    echo root:pnet | chpasswd &>/dev/null
fi

# -----------------------------------------------------------------------------
# SECTION 6 : DÉTECTION DE L'HYPERVISEUR ET REDIMENSIONNEMENT DU DISQUE
# Sur machine physique ("none") ou sous KVM, le volume logique racine est
# étendu à la totalité de l'espace libre, puis le système de fichiers est agrandi
# -----------------------------------------------------------------------------
# detect if pnet run will run under  bare metal or kvm hypervisor
systemd-detect-virt -v >/tmp/hypervisor
resize() {
    ROOTLV=$(mount | grep ' / ' | awk '{print $1}')   # Identifie le volume logique monté sur /
    echo "$ROOTLV"
    lvextend -l +100%FREE "$ROOTLV"                     # Étend le volume logique
    echo Resizing ROOT FS
    resize2fs "$ROOTLV"                                 # Agrandit le système de fichiers
}
fgrep -e kvm -e none /tmp/hypervisor 2>&1 >/dev/null
if [[ $? -eq 0 ]]; then
    grep -q kvm /tmp/hypervisor && resize &>/dev/null
    grep -q none /tmp/hypervisor && resize &>/dev/null
fi

# -----------------------------------------------------------------------------
# SECTION 7 : NETTOYAGE DES PAQUETS INCOMPATIBLES
# Suppression de docker.io, containerd, runc et PHP 8 : ils entrent en
# conflit avec les versions fournies par PNETLab
# -----------------------------------------------------------------------------
apt-get purge -y docker.io containerd runc php8* -q &>/dev/null

# -----------------------------------------------------------------------------
# SECTION 8 : INSTALLATION DES DÉPENDANCES SYSTÈME
# Installation des outils réseau, de PHP 7.4, Apache, MySQL, Tomcat, des
# bibliothèques multimédias et de virtualisation nécessaires à PNETLab
# -----------------------------------------------------------------------------
rm /var/lib/dpkg/lock* &>/dev/null
apt-get install -y ifupdown unzip &>/dev/null
echo -e "${GREEN}Downloading dependencies for PNETLAB ${NO_COLOR}"

sudo apt install -y resolvconf php7.4 php7.4-yaml php7.4-common php7.4-cli php7.4-curl php7.4-gd php7.4-mbstring php7.4-mysql php7.4-sqlite3 php7.4-xml php7.4-zip libapache2-mod-php7.4 libnet-pcap-perl duc libspice-client-glib-2.0-8 libtinfo5 libncurses5 libncursesw5 php-gd ntpdate vim dos2unix apache2 bridge-utils build-essential cpulimit debconf-utils dialog dmidecode genisoimage iptables lib32gcc1 lib32z1 pastebinit php-xml libc6 libc6-i386 libelf1 libpcap0.8 libsdl1.2debian logrotate lsb-release lvm2 ntp php rsync sshpass autossh php-cli php-imagick php-mysql php-sqlite3 plymouth-label python3-pexpect sqlite3 tcpdump telnet uml-utilities zip libguestfs-tools cgroup-tools libyaml-0-2 php-curl php-mbstring net-tools php-zip python2 libapache2-mod-php mysql-server libavcodec58 libavformat58 libavutil56 libswscale5 libfreerdp-client2-2 libfreerdp-server2-2 libfreerdp-shadow-subsystem2-2 libfreerdp-shadow2-2 libfreerdp2-2 winpr-utils gir1.2-pango-1.0 libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 libpangoxft-1.0-0 pango1.0-tools pkg-config libssh2-1 libtelnet2 libvncclient1 libvncserver1 libwebsockets15 libpulse0 libpulse-mainloop-glib0 libssl1.1 libvorbis0a libvorbisenc2 libvorbisfile3 libwebp6 libwebpmux3 libwebpdemux2 libcairo2 libcairo-gobject2 libcairo-script-interpreter2 libjpeg62 libpng16-16 libtool libuuid1 libossp-uuid16 default-jdk default-jdk-headless tomcat9 tomcat9-admin tomcat9-docs libaio1 libasound2 libbrlapi0.7 libcacard0 libepoxy0 libfdt1 libgbm1 libgcc-s1 libglib2.0-0 libgnutls30 libibverbs1 libjpeg8 libncursesw6 libnettle7 libnuma1 libpixman-1-0 libpmem1 librdmacm1 libsasl2-2 libseccomp2 libslirp0 libspice-server1 libtinfo6 libusb-1.0-0 libusbredirparser1 libvirglrenderer1 zlib1g qemu-system-common libxenmisc4.11 libcapstone3 libvdeplug2 libnfs13 udhcpd libxss1  libxencall1 libxendevicemodel1 libxenevtchn1 libxenforeignmemory1 libxengnttab1 libxenstore3.0 libxentoollog1 udhcpd libxss1 libxentoolcore1 libxentoollog1 libxencall1 libxendevicemodel1 libxenevtchn1 libxenmisc4.11 libcapstone3 libvdeplug2 libnfs13 php7.4 php7.4-cli php-common php7.4-curl php7.4-gd php7.4-mbstring php7.4-mysql php7.4-sqlite3 php7.4-xml php7.4-zip libapache2-mod-php7.4

# Définit PHP 7.4 comme version de PHP par défaut
update-alternatives --set php /usr/bin/php &>/dev/null

# -----------------------------------------------------------------------------
# SECTION 9 : TÉLÉCHARGEMENT ET INSTALLATION DES PAQUETS PNETLAB
# Chaque bloc suit la même logique : si le paquet n'est pas déjà installé
# (dpkg-query), il est téléchargé (wget) puis installé (dpkg -i)
# -----------------------------------------------------------------------------
echo -e "${GREEN}Downloading PNETLAB PACKAGES ...${NO_COLOR}"
rm -rf /tmp/* &>/dev/null      # Vide le répertoire temporaire avant les téléchargements
cd /tmp 2>&1 >/dev/null        # Les fichiers seront téléchargés dans /tmp

echo -e "${GREEN}$DOwnload Packages${NO_COLOR}"

# 9.1 Noyau Linux PNETLab
dpkg-query -l | grep linux-image-5.17.15-pnetlab-uksm-2 | grep 5.17.15-pnetlab-uksm-2-1 -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_KERNEL
    unzip /tmp/$KERNEL &>/dev/null
    dpkg -i /tmp/pnetlab_kernel/*.deb
fi

# 9.2 Prérequis Docker (docker-ce)
dpkg-query -l | grep docker-ce -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PRE_DOCKER
    unzip /tmp/pre-docker.zip &>/dev/null
    dpkg -i /tmp/pre-docker/*.deb
fi

# 9.3 Module TPM logiciel (swtpm)
dpkg-query -l | grep swtpm -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PNET_TPM
    unzip /tmp/swtpm-focal.zip &>/dev/null
    dpkg -i /tmp/swtpm-focal/*.deb
fi

# 9.4 Composant Docker de PNETLab
dpkg-query -l | grep pnetlab-docker | grep 6.0.0-30 -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PNET_DOCKER
    dpkg -i /tmp/pnetlab-docker_*.deb
fi

# 9.5 Schéma de base de données
dpkg-query -l | grep pnetlab-schema | grep 6.0.0-30 -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PNET_SCHEMA
    dpkg -i /tmp/pnetlab-schema_*.deb
fi

# 9.6 Guacamole (accès console depuis le navigateur)
dpkg-query -l | grep pnetlab-guacamole | grep 6.0.0-7 -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PNET_GUACAMOLE
    dpkg -i /tmp/pnetlab-guacamole_*.deb
fi

# 9.7 VPCS (postes virtuels légers)
dpkg-query -l | grep pnetlab-vpcs | grep 6.0.0-30 -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PNET_VPC
    dpkg -i /tmp/pnetlab-vpcs_*.deb
fi

# 9.8 Dynamips (émulation de routeurs Cisco)
dpkg-query -l | grep pnetlab-dynamips | grep 6.0.0-30 -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PNET_DYNAMIPS
    dpkg -i /tmp/pnetlab-dynamips_*.deb
fi

# 9.9 Wireshark (capture et analyse de trames)
dpkg-query -l | grep pnetlab-wireshark | grep 6.0.0-30 -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PNET_WIRESHARK
    dpkg -i /tmp/pnetlab-wireshark_6.0.0-30_amd64.deb
fi

# 9.10 QEMU (émulation de machines virtuelles)
dpkg-query -l | grep pnetlab-qemu | grep 6.0.0-30 -q
if [ $? -ne 0 ]; then
    wget --content-disposition -q --show-progress $URL_PNET_QEMU
    dpkg -i /tmp/pnetlab-qemu_*.deb
fi

# -----------------------------------------------------------------------------
# SECTION 10 : CONFIGURATION DU NOM D'HÔTE
# Ajoute l'entrée pnetlab dans /etc/hosts (si absente) et définit le nom de la machine
# -----------------------------------------------------------------------------
fgrep "127.0.1.1 pnetlab.example.com pnetlab" /etc/hosts || echo 127.0.2.1 pnetlab.example.com pnetlab >>/etc/hosts 2>/dev/null
echo pnetlab >/etc/hostname 2>/dev/null

# -----------------------------------------------------------------------------
# SECTION 11 : INSTALLATION DU PAQUET PRINCIPAL PNETLAB
# Ce paquet est installé en dernier, une fois toutes ses dépendances en place
# -----------------------------------------------------------------------------
echo -e "${GREEN}installing pnetlab...${NO_COLOR}"
wget --content-disposition -q --show-progress $URL_PNET_PNETLAB
dpkg -i /tmp/pnetlab_6*.deb

# -----------------------------------------------------------------------------
# SECTION 12 : AJUSTEMENTS SPÉCIFIQUES AUX ENVIRONNEMENTS CLOUD
# Ces fonctions ne s'exécutent que si le cloud correspondant est détecté
# -----------------------------------------------------------------------------
# Detect cloud

# Google Cloud Platform : renommage des interfaces réseau en eth0, activation
# de l'authentification SSH par mot de passe et blocage du noyau GCP d'origine
gcp_tune() {
    cd /sys/class/net/
    for i in ens*; do echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="'$(cat $i/address)'", ATTR{type}=="1", KERNEL=="ens*", NAME="'$i'"'; done >/etc/udev/rules.d/70-persistent-net.rules
    sed -i -e 's/NAME="ens.*/NAME="eth0"/' /etc/udev/rules.d/70-persistent-net.rules
    sed -i -e 's/ens4/eth0/' /etc/netplan/50-cloud-init.yaml
    sed -i -e 's/PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    apt-mark hold linux-image-gcp
    mv /boot/vmlinuz-*gcp /root
    update-grub2
}

# Microsoft Azure : activation de la virtualisation imbriquée (nested KVM)
# et de l'authentification SSH par mot de passe
azure_kernel_tune() {
    apt update
    echo "options kvm_intel nested=1 vmentry_l1d_flush=never" >/etc/modprobe.d/qemu-system-x86.conf
    sed -i -e 's/PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sudo -i
}

# GCP : détection via le BIOS de la machine
dmidecode -t bios | grep -q Google && gcp_tune

# Azure : détection via le nom du noyau
uname -a | grep -q -- "-azure " && azure_kernel_tune

# -----------------------------------------------------------------------------
# SECTION 13 : NETTOYAGE FINAL
# Suppression des paquets devenus inutiles et du cache apt pour libérer de l'espace
# -----------------------------------------------------------------------------
apt autoremove -y -q
apt autoclean -y -q

# -----------------------------------------------------------------------------
# SECTION 14 : MESSAGES DE FIN D'INSTALLATION
# Un redémarrage est obligatoire lors d'une première installation.
# L'outil ishare2 (images) s'installe séparément, après ce redémarrage.
# -----------------------------------------------------------------------------
echo -e "${GREEN}Upgrade has been done successfully ${NO_COLOR}"
echo -e "${GREEN}Default credentials: username=root password=pnet Make sure reboot if you install pnetlab first time ${NO_COLOR}"
```

## 5. Exécution du script

Lancez l'installation en root :

```bash
./install_pnetlab_V6.sh
```

La durée dépend de la connexion Internet et des ressources de la machine. Une fois le message de succès affiché, redémarrez le système. Cette étape est obligatoire lors d'une première installation :

```bash
reboot
```

Après le redémarrage, l'interface web est accessible à l'adresse IP de la machine, dans un navigateur. Passez ensuite à la section 6 pour les vérifications, puis à la section 7 pour installer ishare2.

## 6. Configuration après installation

### 6.1 Nom d'hôte et fichier /etc/hosts

Le nom d'hôte doit être `pnetlab` et être résolu localement. Le fichier `/etc/hosts` doit contenir une ligne de ce type :

```
127.0.0.1 localhost
127.0.1.1 pnetlab.example.com pnetlab
```

Ne modifiez pas le nom d'hôte après l'installation : PNETLab et les images IOL y sont sensibles. Si la machine virtuelle est clonée, contrôlez de nouveau ces éléments.

### 6.2 Bibliothèques 32 bits

Les images IOL sont des binaires 32 bits. Le script installe déjà les principales bibliothèques nécessaires. Pour les ajouter ou les vérifier manuellement :

```bash
dpkg --add-architecture i386
apt update
apt install -y libc6:i386 zlib1g:i386
```

Pour contrôler une image donnée :

```bash
ldd /opt/unetlab/addons/iol/bin/NOM_IMAGE.bin
```

L'absence de ligne `not found` indique que les dépendances sont satisfaites.

### 6.3 Réseau et DNS

ishare2 doit résoudre des noms de domaine (pnetlab.com, GitHub, LabHub). Un DNS absent provoque l'erreur `Failed to download the JSON index file`.

Tests à effectuer :

```bash
ping -c2 8.8.8.8          # test de la connexion IP
ping -c2 pnetlab.com      # test de la résolution DNS
cat /etc/resolv.conf      # serveurs DNS utilisés
```

Interprétation :

| Résultat | Diagnostic |
|---|---|
| `8.8.8.8` répond mais pas `pnetlab.com` | Problème de DNS |
| Aucun des deux ne répond | Problème de passerelle ou de carte réseau de la machine |

**Cas standard (fichier /etc/network/interfaces).** Le script installe `ifupdown`, et PNETLab gère normalement son réseau par ce fichier. Ajoutez la directive suivante dans le bloc de l'interface concernée (en général `pnet0`), puis redémarrez le service :

```
dns-nameservers 8.8.8.8 1.1.1.1
```

```bash
systemctl restart networking
```

**Exemple : machine connectée en Wi-Fi avec netplan.** Éditez le fichier de configuration et restreignez ses droits, car il contient le mot de passe du Wi-Fi :

```bash
nano /etc/netplan/01-wifi.yaml
chmod 600 /etc/netplan/01-wifi.yaml
```

```yaml
network:
  version: 2
  wifis:
    wlan0:
      dhcp4: true
      optional: true
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      access-points:
        "NOM_DU_WIFI":
          password: "MOT_DE_PASSE"
```

Appliquez la configuration et vérifiez :

```bash
netplan apply
ip a show wlan0           # doit afficher une adresse IP
resolvectl status         # doit lister 8.8.8.8 et 1.1.1.1
ping -c2 pnetlab.com
```

Remarques sur ce montage :

1. L'interface `wlan0` porte l'accès Internet et l'adresse permettant d'ouvrir l'interface web (par exemple `http://192.168.1.57`). Cette adresse peut changer avec le DHCP : réservez l'adresse IP dans la box.
2. L'interface `eth0` est rattachée au bridge `pnet0` de PNETLab. Sans câble branché (état `NO-CARRIER`), les nœuds reliés à `Cloud0` n'ont aucun accès au réseau extérieur, et le Wi-Fi ne peut pas être ponté simplement. Pour donner un accès Internet aux nœuds, utilisez un accès NAT ou branchez un câble sur `eth0`.
3. Ne partagez jamais ce fichier sans avoir masqué le mot de passe du Wi-Fi.

## 7. Installation et utilisation d'ishare2

ishare2 est un utilitaire en ligne de commande qui permet de rechercher et de télécharger des images (IOL, QEMU, Dynamips) directement dans PNETLab. Il nécessite un accès Internet. Le dépôt à utiliser est `ishare2-org/ishare2-cli` : l'ancien dépôt `pnetlabrepo/ishare2` n'est plus maintenu.

### 7.1 Installation

Une fois PNETLab installé et la machine redémarrée, connectez-vous en root et exécutez :

```bash
apt install -y git
git clone https://github.com/ishare2-org/ishare2-cli.git

mkdir -p /opt/ishare2/cli
cp -r ishare2-cli/* /opt/ishare2/cli/

cp /opt/ishare2/cli/ishare2 /usr/sbin/ishare2
chmod +x /usr/sbin/ishare2
```

Lancez ensuite ishare2 une première fois pour terminer son initialisation :

```bash
ishare2
```

Les lancements suivants se font avec la même commande. Pour contrôler l'installation :

```bash
which ishare2
```

Une méthode alternative en une ligne est proposée par le projet (`curl https://ishare2.sh/install | sh`). Comme pour tout script exécuté directement depuis Internet, consultez son contenu avant de l'utiliser.

### 7.2 Vérification de la connectivité

```bash
ishare2 test
```

Cette commande vérifie que les dépôts (GitHub, LabHub) sont accessibles. Si tous les tests sont concluants, l'outil est opérationnel. En cas d'échec, consultez la section 6.3.

### 7.3 Recherche d'images

Les images IOL sont légères et adaptées aux machines disposant de peu de mémoire, par exemple 4 Go de RAM.

```bash
ishare2 search bin
```

Une liste numérotée s'affiche. Pour filtrer par type d'équipement :

```bash
ishare2 search bin | grep -i l3     # routeurs
ishare2 search bin | grep -i l2     # commutateurs
```

| Type d'image | Usage | Template PNETLab |
|---|---|---|
| L3 (par exemple `i86bi_linux`) | Routage | Template IOL standard |
| L2 (par exemple `i86bi_linux_l2`) | Commutation | Template IOL « L2 » |

Il ne faut pas mélanger les deux : choisissez le bon template selon l'image.

Autres types d'images :

```bash
ishare2 search qemu
ishare2 search dynamips
ishare2 search all
```

### 7.4 Téléchargement d'une image

Remplacez `<number>` par l'identifiant de l'image dans la liste obtenue à l'étape précédente :

```bash
ishare2 pull bin <number>
```

### 7.5 Vérification des images installées

```bash
ishare2 installed bin
```

### 7.6 Récapitulatif des commandes

| Commande | Fonction |
|---|---|
| `ishare2 test` | Vérifier la connectivité aux dépôts |
| `ishare2 search bin` | Lister les images IOL disponibles |
| `ishare2 pull bin <number>` | Télécharger l'image portant l'identifiant indiqué |
| `ishare2 installed bin` | Afficher les images IOL déjà installées |
| `ishare2 gui install` | Installer l'interface web d'ishare2 |
| `ishare2 upgrade` | Mettre à jour ishare2 |

L'interface web d'ishare2 est signalée par ses auteurs comme étant en développement et potentiellement instable. Elle doit être exécutée en root, car elle accède au répertoire `/opt/unetlab`. La commande `ishare2 upgrade` propose également des mises à jour de PNETLab : utilisez-la avec prudence sur une installation réalisée par script.

## 8. Emplacement des images et permissions

Les images IOL sont placées dans :

```
/opt/unetlab/addons/iol/bin/
```

Après chaque ajout d'image, quelle que soit la méthode (ishare2 ou transfert manuel), corrigez les permissions :

```bash
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions
```

Sans cette étape, l'image n'apparaît pas correctement ou le nœud s'éteint dès son démarrage.

## 9. Mode Offline de PNETLab

PNETLab propose deux modes de connexion : Online (compte PNETLab, accès complet au Store) et Offline (compte local, sans Internet).

| | Online | Offline |
|---|---|---|
| Internet nécessaire | Oui | Non |
| Compte | Enregistré sur pnetlab.com | Local : `admin` / `pnet` par défaut |
| Labs du Store | Tous | Uniquement les « Open Labs » |

Le mode actuel est visible dans l'interface web, menu System puis System Mode.

Commandes en ligne (SSH sur la machine) :

```bash
mode default offline    # mode par défaut à la connexion : offline
mode default online     # mode par défaut à la connexion : online
mode reset offline      # réinitialise le mot de passe du compte offline
mode reset all          # remet les modes à l'état d'origine
```

Points d'attention :

1. Si le mode Offline n'a jamais été activé depuis l'interface (en étant connecté en Online), la commande `mode default offline` ne suffit pas toujours : la page peut afficher « OFFLINE Mode is disabled ». Il faut alors l'activer une première fois après une connexion Online (System puis System Mode).
2. En mode Offline, changez le mot de passe `admin` / `pnet` dès la première connexion.
3. Pour ouvrir les consoles en mode natif (telnet, VNC, Wireshark), installez le client pack (PuTTY, UltraVNC, Wireshark) sur le poste de travail. La console HTML5 fonctionne sans installation.
4. Le mode Offline ne signifie pas qu'ishare2 fonctionne hors ligne : `ishare2 search` et `ishare2 pull` ont besoin d'Internet. Téléchargez les images au préalable, ou transférez-les manuellement avec WinSCP ou FileZilla dans `/opt/unetlab/addons/...`, puis exécutez `fixpermissions` (section 8).

## 10. Identifiants par défaut

| Accès | Identifiant | Mot de passe |
|---|---|---|
| Système (SSH, console) | root | pnet |
| Interface web PNETLab (mode Offline) | admin | pnet |

Il est fortement recommandé de modifier ces mots de passe dès la première connexion, en particulier si la machine est accessible depuis un réseau non maîtrisé.

## 11. Dépannage

### 11.1 Tableau des symptômes courants

| Symptôme | Cause probable | Solution |
|---|---|---|
| Message « Upgrade has been rejected » | Version d'Ubuntu différente de la 20.04 | Utiliser une installation d'Ubuntu 20.04 |
| Erreur `bad interpreter` au lancement | Fins de ligne Windows | Exécuter `dos2unix install_pnetlab_V6.sh` |
| Erreur de verrou dpkg | Un autre processus apt est en cours | Attendre la fin du processus, puis relancer le script |
| `Failed to download the JSON index file` ou échec de `ishare2 test` | DNS absent, dépôts inaccessibles ou pare-feu restrictif | Suivre la section 6.3 |
| Image téléchargée non visible ou nœud qui s'éteint au démarrage | Permissions non corrigées | Exécuter `fixpermissions` (section 8) |
| `not found` ou `No such file` avec `ldd` | Bibliothèques 32 bits manquantes | Suivre la section 6.2 |
| `invalid license` | Licence Cisco absente ou non valide pour cette image | Voir la note légale (section 13) |
| `Segmentation fault` | Image potentiellement corrompue ou mémoire insuffisante | Retélécharger l'image avec ishare2 et contrôler la RAM disponible |
| `unable to open NETMAP` | Message normal lors d'un lancement manuel | Aucune action nécessaire |

### 11.2 Tester une image à la main

Lorsqu'un routeur s'éteint au démarrage, lancez l'image manuellement pour lire le message d'erreur :

```bash
cd /opt/unetlab/addons/iol/bin
export IOURC=/opt/unetlab/addons/iol/bin/iourc
./NOM_IMAGE.bin 1
```

Le fichier `iourc` doit contenir la licence Cisco dont vous disposez légitimement.

### 11.3 Autres vérifications

```bash
tail -20 /opt/unetlab/data/Logs/unl_wrapper.txt   # journaux du wrapper
ps aux | grep i86bi                               # le processus IOL tourne-t-il ?
free -m                                           # mémoire disponible
```

## 12. Bonnes pratiques

1. Faire un snapshot de la machine virtuelle lorsque tout fonctionne.
2. Ne jamais changer le nom d'hôte `pnetlab`.
3. Toujours lancer `fixpermissions` après un téléchargement ou un transfert d'image.
4. Ne pas mélanger les images L2 et L3 : choisir le bon template.
5. Changer les mots de passe par défaut.
6. Ne jamais publier de fichiers de configuration contenant des mots de passe ou des clés.

## 13. Avertissement et note légale

Le script télécharge des paquets depuis des sources tierces. Vérifiez leur provenance avant de l'exécuter sur un environnement de production.

Les images IOL et leurs licences appartiennent à Cisco. Ce document ne décrit pas de méthode pour générer des licences : il vous appartient de disposer des droits nécessaires pour utiliser ces images. Pour un usage légitime et durable, l'option officielle est Cisco Modeling Labs (CML).
