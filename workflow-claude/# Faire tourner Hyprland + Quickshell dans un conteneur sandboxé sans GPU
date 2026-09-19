Ce guide documente comment obtenir un vrai Hyprland (0.56+, avec config Lua) et Quickshell
qui tournent, se composent ensemble, et sont capturables en screenshot — à l'intérieur d'un
conteneur Linux sandboxé (type Claude's bash tool) qui au départ :
- n'a **aucun** `/dev/dri` (pas de GPU réel, pas même virtuel)
- a un noyau hôte compilé **sans `CONFIG_DRM`** (donc aucune astuce userspace ne peut créer
  de périphérique DRM sur ce noyau, `vgem` inclus — vérifier via
  `zcat /proc/config.gz | grep CONFIG_DRM` ou équivalent)
- est basé sur une distribution (ex. Ubuntu 24.04 "Noble") plus ancienne que celle dont on a
  besoin pour les paquets voulus (ex. Ubuntu 25.04 "Plucky" pour un Hyprland récent)
- a un accès réseau restreint à une allowlist (typiquement : `github.com`,
  `archive.ubuntu.com`, `pypi.org`, `npmjs.com`... mais **pas** `gitlab.freedesktop.org`,
  ni les PPA Launchpad, ni les serveurs de la plupart des forges tierces)

**Principe général : ne jamais mélanger les générations.** Toute tentative de faire tourner
un binaire compilé pour une distribution plus récente directement sur le système hôte plus
ancien (via un sysroot partiel, un `LD_LIBRARY_PATH` bricolé, etc.) finit par un crash ABI
insidieux (`stack smashing`, `SIGSEGV` aléatoire) qui peut prendre des heures à diagnostiquer.
La seule approche fiable est de construire un **chroot complet et cohérent** de la distribution
cible, et d'y compiler avec son propre toolchain.

---

## Partie 1 — Obtenir un vrai GPU virtuel (`/dev/dri`)

Le noyau de l'hôte n'a pas DRM. Il faut donc démarrer un **second noyau**, complet, dans une
VM QEMU émulée (pas besoin de KVM — le mode TCG logiciel suffit, juste plus lent).

### 1.1 Installer un noyau complet et QEMU via apt
```bash
apt-get install -y linux-image-generic qemu-system-x86
# Donne /boot/vmlinuz-X.Y.Z-generic et /boot/initrd.img-X.Y.Z-generic
```

### 1.2 Extraire les modules noyau nécessaires (ils sont compressés .zst)
Le driver `virtio_gpu` (et sa dépendance `virtio_dma_buf`) sont fournis par le paquet noyau
mais compressés. `insmod`/`busybox insmod` ne savent PAS décompresser le zstd automatiquement :
```bash
cd /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/virtio
cp virtio-gpu.ko.zst /chemin/de/travail/ && unzstd --rm virtio-gpu.ko.zst
cd /lib/modules/$(uname -r)/kernel/drivers/virtio
cp virtio_dma_buf.ko.zst /chemin/de/travail/ && unzstd --rm virtio_dma_buf.ko.zst
```
Créer un petit disque ext4 (image `dd` + `mkfs.ext4`) contenant ces deux `.ko` décompressés
et un binaire `busybox` statique (`apt-get install busybox-static`, ou `apt-get download` +
extraction), pour pouvoir charger les modules depuis l'`initramfs` minimal (qui n'a pas de
`kmod`/`modprobe` opérationnel avant le vrai `init`).

### 1.3 Lancer QEMU avec un GPU virtio
```bash
qemu-system-x86_64 \
  -kernel /boot/vmlinuz-X.Y.Z-generic \
  -initrd /boot/initrd.img-X.Y.Z-generic \
  -append "console=ttyS0 root=/dev/vda rw init=/bin/bash" \
  -device virtio-gpu-pci \
  -drive file=rootdisk.img,format=raw,if=virtio \
  -drive file=utildisk.img,format=raw,if=virtio \
  -m 2048 -smp 1 -nographic \
  -chardev socket,id=char0,path=/tmp/vm-serial.sock,server=on,wait=off \
  -serial chardev:char0 -monitor none -no-reboot
```
`init=/bin/bash` court-circuite systemd pour un accès shell root immédiat et rapide.
**Ne PAS essayer `virtio-gpu-gl-pci` + `-display egl-headless`** : ça nécessite un vrai GPU/EGL
côté hôte QEMU lui-même, qui n'existe pas non plus dans ce genre de sandbox — testé, échoue
avec `opengl is not available`, aucun contournement possible.

### 1.4 Piloter la VM depuis un script (pas de TTY interactif)
Se connecter en Python au socket série pour envoyer des commandes et lire la sortie :
```python
import socket, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect("/tmp/vm-serial.sock")
def cmd(c, wait=3):
    s.sendall(c.encode()+b"\n"); time.sleep(wait)
    data = b""; s.settimeout(1)
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk: break
            data += chunk
    except socket.timeout: pass
    print(data.decode(errors='replace'))
```

### 1.5 Une fois dans la VM : monter les FS et charger le GPU
```bash
mount -t proc proc /proc
mkdir -p /dev/pts && mount -t devpts devpts /dev/pts
mkdir -p /dev/shm && mount -t tmpfs tmpfs /dev/shm
mkdir -p /mnt/util && mount /dev/vdb /mnt/util   # le disque utilitaire
/mnt/util/busybox insmod /mnt/util/virtio_dma_buf.ko
/mnt/util/busybox insmod /mnt/util/virtio-gpu.ko
chmod 666 /dev/dri/card0 /dev/dri/renderD128
```
Vérifier : `ls /dev/dri` doit montrer `card0` et `renderD128`.

**Piège important** : ce GPU virtio n'a **aucune accélération 3D** (`virgl=off` par défaut,
et on ne peut pas l'activer faute de GPU côté hôte). Les compositeurs Wayland tomberont donc
en repli logiciel (`kms_swrast` / Mesa llvmpipe). C'est suffisant pour du rendu correct, mais
plus lent, et certaines versions de logiciels gèrent ce repli mieux que d'autres (voir Partie 4).

---

## Partie 2 — Construire un chroot cohérent de la distribution cible

**Ne jamais** faire un sysroot partiel (copier juste quelques `.so`/headers dans l'hôte).
Utiliser `debootstrap` pour un vrai système de fichiers complet :

```bash
apt-get install -y debootstrap
debootstrap --arch=amd64 --variant=minbase plucky /opt/plucky-chroot http://archive.ubuntu.com/ubuntu
```
(remplacer `plucky` par le nom de code de la distribution cible)

### 2.1 Monter les pseudo-FS avant tout usage du chroot
```bash
mount --bind /proc /opt/plucky-chroot/proc
mount --bind /dev  /opt/plucky-chroot/dev
mount --bind /sys  /opt/plucky-chroot/sys
```
**Ces montages ne survivent pas entre deux appels d'outils séparés** dans un environnement
comme celui-ci (le process meurt/le mount se démonte à la frontière). Il faut soit tout
regrouper dans un seul appel, soit vérifier/remonter (`mountpoint -q ... || mount --bind ...`)
au début de chaque nouvelle séquence.

### 2.2 Réseau dans le chroot : le certificat CA du proxy sandbox
Si le sandbox utilise un proxy d'egress qui fait du TLS interception (souvent le cas), `git
clone`/`curl` échoueront dans le chroot avec `self-signed certificate in certificate chain`
tant qu'on n'a pas copié le certificat CA de l'hôte :
```bash
cp /usr/local/share/ca-certificates/*.crt /opt/plucky-chroot/usr/local/share/ca-certificates/
chroot /opt/plucky-chroot update-ca-certificates
```

### 2.3 sources.list minimal
```bash
echo "deb [trusted=yes] http://archive.ubuntu.com/ubuntu plucky main universe" \
  > /opt/plucky-chroot/etc/apt/sources.list
chroot /opt/plucky-chroot apt-get update
```

---

## Partie 3 — Compiler Hyprland (version récente) depuis les sources

Pour une version de Hyprland trop récente pour être dans les dépôts (ex. 0.55/0.56 avec
config Lua), il faut compiler toute la chaîne de dépendances maison, dans l'ordre :

```
hyprutils → hyprwayland-scanner → hyprland-protocols → hyprlang
  → aquamarine → hyprcursor → hyprgraphics → hyprwire → Hyprland
```

Tous ces dépôts sont sur `github.com/hyprwm/<nom>` (accessible même avec une allowlist
restrictive). Pour chacun :
```bash
cd /tmp/<repo> && cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
ninja -C build -j2 && ninja -C build install && ldconfig
```
(exécuter via `chroot /opt/plucky-chroot /bin/bash -c "..."`)

### 3.1 Dépendances système à installer via apt au fil des erreurs `cmake`
`cmake`/`pkg-config` vous diront ce qui manque un par un — ne pas essayer de tout deviner à
l'avance. Liste type rencontrée : `cmake ninja-build pkg-config wayland-protocols
libwayland-dev libdrm-dev libgbm-dev libegl-dev libseat-dev libdisplay-info-dev hwdata
libinput-dev libudev-dev libzip-dev librsvg2-dev libtomlplusplus-dev libmagic-dev libpng-dev
libpugixml-dev glslang-dev glslang-tools libpam0g-dev libpolkit-agent-1-dev libcli11-dev
libudis86-dev libsdbus-c++-dev libmuparser-dev libre2-dev liblcms2-dev libcanberra-dev
libeis-dev libxcb-icccm4-dev libxcb-composite0-dev libxcb-res0-dev libxcb-errors-dev
libpixman-1-dev uuid-dev libcairo2-dev libpango1.0-dev libxcursor-dev libreadline-dev
meson`. `glaze` (JSON C++ header-only) est récupéré automatiquement par `FetchContent` de
CMake, pas besoin de le cloner à la main.

### 3.2 Obstacles réels rencontrés, et comment les lever

**a) Lua trop récent pour la distribution.** Si Hyprland exige `lua>=5.5,<5.6` et que la
distribution n'a que 5.4 : compiler Lua soi-même (c'est trivial, zéro dépendance) :
```bash
git clone --branch v5.5.1 https://github.com/lua/lua.git
cd lua && make PLAT=linux CFLAGS='-O2 -fPIC -DLUA_USE_LINUX'
gcc -shared -o liblua5.5.so.5.5.1 -Wl,-soname,liblua5.5.so.5.5 *.o -lm -ldl
cp liblua5.5.so.5.5.1 /usr/lib/x86_64-linux-gnu/
ln -sf liblua5.5.so.5.5.1 /usr/lib/x86_64-linux-gnu/liblua5.5.so.5.5
ln -sf liblua5.5.so.5.5 /usr/lib/x86_64-linux-gnu/liblua5.5.so
mkdir -p /usr/include/lua5.5 && cp lua.h lualib.h lauxlib.h luaconf.h /usr/include/lua5.5/
# Créer aussi le wrapper C++ manquant lua.hpp :
cat > /usr/include/lua5.5/lua.hpp <<'EOF'
extern "C" { #include "lua.h" #include "lualib.h" #include "lauxlib.h" }
EOF
# Fichier .pc pour pkg-config, nommé EXACTEMENT comme le nom cherché par cmake (ex. lua5.5.pc) :
cat > /usr/lib/x86_64-linux-gnu/pkgconfig/lua5.5.pc <<'EOF'
prefix=/usr
libdir=${prefix}/lib/x86_64-linux-gnu
includedir=${prefix}/include/lua5.5
Name: Lua
Version: 5.5.1
Libs: -L${libdir} -llua5.5
Cflags: -I${includedir}
EOF
```

**b) `xkbcommon`/`libinput` trop anciens.** Cloner et compiler depuis GitHub (xkbcommon) ou
un miroir GitHub non-officiel (libinput n'a pas de miroir officiel ; `mix-mirror/libinput`
sur GitHub fonctionne) :
```bash
git clone https://github.com/xkbcommon/libxkbcommon.git   # puis git checkout xkbcommon-1.13.2
git clone https://github.com/mix-mirror/libinput.git       # puis git checkout 1.32.0
# xkbcommon : meson setup build --prefix=/usr --buildtype=release -Denable-x11=false
# libinput  : meson setup build --prefix=/usr --buildtype=release -Ddebug-gui=false -Dtests=false
```

**c) `wayland-protocols` trop ancien, ET certains protocoles (ex. `color-management-v1`)
manquent des évolutions récentes (nouvelles entrées d'énum, nouvelles requêtes).**
`gitlab.freedesktop.org` est bloqué par l'allowlist. Solution : chercher un projet tiers qui
vendorise une copie à jour du fichier XML et qui a un miroir GitHub (SDL — `libsdl-org/SDL` —
en avait une bien plus récente que Ubuntu LTS) :
```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/libsdl-org/SDL.git
cd SDL && git sparse-checkout set wayland-protocols
cp wayland-protocols/color-management-v1.xml /usr/share/wayland-protocols/staging/color-management/
```
Si même ça ne suffit pas (projet très bleeding-edge), **patcher le XML à la main** en suivant
le modèle d'une entrée existante similaire (ex. ajouter `windows_bt2100` sur le modèle de
`windows_scrgb` déjà présent : même structure d'`<entry>` dans l'`<enum>`, même structure de
`<request>`). Après toute modification du XML, supprimer les fichiers `.cpp`/`.hpp` déjà
générés dans `Hyprland/protocols/` pour forcer leur régénération par `hyprwayland-scanner`
au prochain `ninja`.

**d) GCC trop ancien pour `#embed` (C23/C++26).** Certaines versions récentes de Hyprland
utilisent `#embed` pour intégrer un fichier directement. GCC ne le supporte qu'à partir de
la version 15. Si la distribution cible propose gcc-15 en paquet (ex. `apt-cache policy
gcc-15 g++-15`), l'installer et reconfigurer avec
`-DCMAKE_C_COMPILER=gcc-15 -DCMAKE_CXX_COMPILER=g++-15`. **Ceci ne fonctionne que si on est
dans un vrai chroot cohérent** — essayer de lancer un GCC natif d'une distribution plus
récente en dehors d'un chroot (juste avec un `LD_LIBRARY_PATH` bricolé) plante avec un
`SIGSEGV`/`mmap` dès le chargement de `cc1plus`, sans rapport avec `#embed` lui-même.

**e) Fonctions de bibliothèque standard C++23/26 pas encore implémentées par ce GCC**,
même une fois `#embed` disponible (l'implémentation de la stdlib est indépendante du
support syntaxique du compilateur) :
- `std::vector::append_range(x)` → remplacer par
  `{ auto&& tmp = (x); vec.insert(vec.end(), tmp.begin(), tmp.end()); }`
  (utiliser `auto&&`, pas `std::ranges::begin/end` sur un objet temporaire non nommé — les
  algorithmes de `<ranges>` refusent les prvalues non nommées comme "borrowed range")
- `std::ranges::starts_with(range, prefix)` → remplacer par une boucle manuelle comparant
  élément par élément
- `std::string::subview(...)` (méthode très récente, quasi expérimentale) → remplacer
  simplement par `.substr(...)` si le résultat sert juste à un affichage/log (accepte une
  petite allocation supplémentaire sans conséquence fonctionnelle)

Rechercher chaque usage avec `grep -rn "append_range\|starts_with\|subview(" src/` avant de
lancer un nouveau build, pour patcher plusieurs occurrences d'un coup plutôt qu'une par une.

### 3.3 Gestion de l'espace disque
Compiler tout ceci consomme énormément d'espace (sources + `build/` de chaque lib + PCH +
objets `-O3`). Nettoyer agressivement au fur et à mesure :
```bash
rm -rf /opt/<chroot>/tmp/<lib>/build   # dès qu'une lib est installée, son build/ est inutile
```
Si le disque sature en cours de compilation de Hyprland lui-même (gros consommateur avec
`-O3` + PCH), reconfigurer avec `-DCMAKE_CXX_FLAGS='-O1' -DCMAKE_C_FLAGS='-O1'` — accélère
aussi la compilation. `ninja` reprend où il s'est arrêté après une interruption : jamais besoin
de tout recompiler depuis zéro après un `rm -rf build`, sauf changement des flags cmake.

### 3.4 Robustesse des process en arrière-plan
Dans un environnement où chaque appel d'outil peut tuer les process de la commande précédente,
lancer les compilations longues avec `setsid` (pas juste `&`) et rediriger vers un fichier de
log avec capture explicite du code de sortie :
```bash
setsid bash -c "cd /opt/chroot/tmp/Hyprland && ninja -C build -j2 > /tmp/build.log 2>&1; echo EXIT_CODE=\$? >> /tmp/build.log" < /dev/null > /dev/null 2>&1 &
```
Puis revenir périodiquement lire la fin du log et vérifier `ps aux | grep ninja` — si le
process a disparu sans `EXIT_CODE` dans le log, c'est qu'il a été tué par la frontière entre
deux appels ; relancer la même commande (elle reprendra où `ninja` s'était arrêté).

---

## Partie 3bis — Compiler Quickshell lui-même

Quickshell n'est pas packagé dans les dépôts standards de la plupart des distributions. Le
paquet Qt fourni par la distribution cible doit être suffisamment récent (Quickshell exige au
minimum Qt 6.6.0 — vérifier `dpkg -l qt6-base-dev` avant de commencer ; si c'est trop vieux,
inutile d'insister, il faut une distribution plus récente, pas de solution de contournement
propre).

### 3bis.1 Dépendances système
```bash
apt-get install -y cmake ninja-build \
  qt6-base-dev qt6-declarative-dev qt6-declarative-dev-tools \
  qt6-wayland qt6-wayland-dev qt6-wayland-private-dev qt6-wayland-dev-tools \
  qt6-base-private-dev qt6-shadertools-dev \
  wayland-protocols libpipewire-0.3-dev libdbus-1-dev libxkbcommon-dev \
  libcli11-dev libdrm-dev libgbm-dev libegl-dev libegl1-mesa-dev \
  libpam0g-dev libpolkit-agent-1-dev libjemalloc-dev
```
Ces paquets `-private-dev`/`-dev-tools` (notamment `qt6-wayland-private-dev`) sont souvent
oubliés au premier passage — `cmake` échouera sur `Qt::WaylandClientPrivate includes
non-existent path` sans eux. Les ajouter avant de relancer la configuration plutôt que
d'essayer de contourner l'erreur.

### 3bis.2 Cloner et configurer
```bash
git clone --depth 1 https://github.com/quickshell-mirror/quickshell.git
cd quickshell
cmake -B build -G Ninja -DCRASH_HANDLER=OFF
```
`-DCRASH_HANDLER=OFF` est important : sans lui, `cmake` cherche `cpptrace`, une bibliothèque
qui n'est packagée dans quasiment aucune distribution et qu'il faudrait sinon compiler depuis
les sources pour rien (elle ne sert qu'aux rapports de crash détaillés).

### 3bis.3 Résoudre les derniers manques au fil de l'eau
Selon la distribution, `cmake` peut encore réclamer `CLI11` (déjà couvert par
`libcli11-dev` ci-dessus) ou des en-têtes DRM/EGL manquants — les ajouter un par un via
`apt-cache search`/`apt-get install` plutôt que de deviner à l'avance.

### 3bis.4 Compiler et installer
```bash
ninja -C build -j2
ninja -C build install     # ou utiliser directement build/src/quickshell sans installer
```
Le binaire final se trouve dans `build/src/quickshell` (environ 200 Mo, PIE, non strippé par
défaut). C'est ce chemin qu'on utilise ensuite dans la Partie 4 pour le lancer contre le
socket Wayland de Hyprland. Si l'espace disque est limité (voir 3.3), il est possible de
copier uniquement ce binaire final (`cp build/src/quickshell /usr/local/bin-saved/`) puis de
supprimer tout le dossier `build/` et les sources, une fois la compilation confirmée réussie.

---

## Partie 4 — Faire tourner Hyprland + Quickshell ensemble

### 4.1 Créer le disque de démarrage complet de la VM
Une fois le chroot prêt (avec Hyprland installé), en faire une image disque via `rsync`
(pas juste `cp`, pour préserver les permissions/nœuds spéciaux) :
```bash
dd if=/dev/zero of=rootdisk.img bs=1M count=4500   # prévoir large : chroot + marge ext4
mkfs.ext4 -F rootdisk.img
mount -o loop rootdisk.img /mnt/rootdisk-mnt
rsync -aHAX --numeric-ids /opt/plucky-chroot/ /mnt/rootdisk-mnt/
umount /mnt/rootdisk-mnt
```
Ne pas oublier de copier `/lib/modules/$(uname -r)` de l'**hôte** dans le chroot avant cette
étape, pour que la VM (qui utilise le même noyau que l'hôte, chargé via QEMU) trouve ses
modules au bon endroit une fois `root=/dev/vda` monté comme vraie racine.

### 4.2 Lancer Hyprland en mode headless dans la VM
```bash
export XDG_RUNTIME_DIR=/run/user/0
export WLR_BACKENDS=headless
Hyprland --i-am-really-stupid    # nécessaire pour autoriser le lancement en root
```
Une fois lancé, vérifier `ls $XDG_RUNTIME_DIR` → doit montrer `wayland-1`.

### 4.3 Lancer Quickshell dessus
```bash
export WAYLAND_DISPLAY=wayland-1
export QT_QUICK_BACKEND=software   # important : force le rendu logiciel Qt Quick
quickshell -p /chemin/vers/shell.qml
```
Sans `QT_QUICK_BACKEND=software`, Quickshell tente un rendu accéléré via EGL/DRM qui peut
échouer silencieusement selon l'état du GPU virtio (sans accélération 3D).

### 4.4 QML : fond d'écran + barre, via le vrai protocole layer-shell
Hyprland supporte nativement `wlr-layer-shell` (contrairement à `weston`, qui n'implémente
que son propre protocole de shell — avec `weston`, `PanelWindow` échoue avec `Failed to
initialize layershell integration` et ne s'affiche jamais). Syntaxe qui fonctionne :
```qml
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Background   // fond d'écran
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        Rectangle { anchors.fill: parent; color: "#24283b" }
    }
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Top          // barre
        anchors { top: true; left: true; right: true }
        implicitHeight: 34
        exclusiveZone: 34
        RowLayout { anchors.fill: parent /* ... */ }
    }
}
```

### 4.5 Capturer un screenshot réel
`weston-screenshooter` ne fonctionne PAS avec Hyprland (protocole différent). Il faut un
client `wlr-screencopy` (protocole `zwlr_screencopy_manager_v1`, bien supporté par
Hyprland/wlroots) :
```bash
git clone --depth 1 https://github.com/swaywm/wlroots.git   # pour le fichier XML + un exemple client tout fait
# fichiers utiles : protocol/wlr-screencopy-unstable-v1.xml et examples/screencopy.c
wayland-scanner client-header wlr-screencopy-unstable-v1.xml wlr-screencopy-unstable-v1-client-protocol.h
wayland-scanner private-code  wlr-screencopy-unstable-v1.xml wlr-screencopy-unstable-v1-client-protocol.c
gcc -o screencopy screencopy.c wlr-screencopy-unstable-v1-client-protocol.c \
  $(pkg-config --cflags --libs wayland-client libpng)
XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1 ./screencopy
# écrit wayland-screenshot.png dans le répertoire courant
```
**Piège observé** : avec une ancienne version de Hyprland/wlroots (0.41.2 dans nos tests),
le protocole `screencopy` négocie le format correctement (callback `buffer` reçu) mais la
copie de frame ne se termine **jamais** (ni `ready` ni `failed`) quand le rendu tombe en repli
logiciel pur — confirmé en attendant 70+ secondes, ce n'est pas un problème de lenteur mais un
vrai gap fonctionnel de cette version dans ce scénario précis. Une version plus récente
(0.56.0 dans nos tests, avec `aquamarine` à la place de `wlroots`) a correctement complété la
capture dans la même configuration matérielle. Si la capture reste bloquée indéfiniment,
essayer d'abord une version plus récente avant de chercher un bug ailleurs.

### 4.6 Faire sortir le fichier de la VM
Le plus simple : dédier un petit disque `virtio-blk` "utilitaire" (`utildisk.img`, quelques
dizaines de Mo), monté à la fois par la VM et par l'hôte à tour de rôle (jamais simultanément
en écriture des deux côtés). Écrire le screenshot dedans côté VM, `sync; umount` côté VM,
puis `mount -o loop utildisk.img /mnt/... ` côté hôte pour le récupérer.

---

## Résumé express (checklist)

1. `apt-get install linux-image-generic qemu-system-x86 debootstrap busybox-static`
2. Extraire+décompresser `virtio-gpu.ko` et `virtio_dma_buf.ko` (`.zst` → `unzstd --rm`)
3. `debootstrap` la distribution cible dans un chroot, `mount --bind proc/dev/sys`, copier le
   certificat CA du proxy sandbox si besoin
4. Compiler la chaîne de dépendances Hyprland (hyprutils → ... → Hyprland) en résolvant
   chaque erreur `cmake` au fil de l'eau via `apt`, source GitHub, ou patch manuel de dernier
   recours ; compiler Quickshell séparément (`-DCRASH_HANDLER=OFF`, dépendances Qt6
   `-private-dev`)
5. `rsync` le chroot fini vers une image disque `ext4`
6. Booter QEMU/TCG avec `virtio-gpu-pci` + cette image + le disque utilitaire, `init=/bin/bash`
7. Charger les modules GPU manuellement, lancer `Hyprland --i-am-really-stupid` en
   `WLR_BACKENDS=headless`, puis `quickshell` avec `QT_QUICK_BACKEND=software`
8. Compiler un client `wlr-screencopy` minimal pour extraire une image PNG réelle
9. Faire ressortir le fichier via le disque utilitaire partagé

**Piège transversal à ne jamais oublier** : dans ce genre de sandbox, les process lancés en
arrière-plan (`&`, même avec `nohup`) peuvent mourir silencieusement à la frontière entre deux
appels d'outils. Toujours utiliser `setsid`, rediriger vers un log avec code de sortie explicite,
et revérifier `ps aux` après chaque étape critique avant de supposer qu'un process est mort ou
que quelque chose a échoué.
