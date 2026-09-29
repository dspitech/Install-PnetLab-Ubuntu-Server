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
