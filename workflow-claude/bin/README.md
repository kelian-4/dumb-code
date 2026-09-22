# bin/ — Hyprland + Quickshell precompiles (sandbox sans GPU)

Binaires et fichiers reutilisables issus d'une compilation reelle et
fonctionnelle de Hyprland 0.56+ (config Lua) et Quickshell, realisee dans un
conteneur sandbox Ubuntu 24.04 sans `/dev/dri` ni `CONFIG_DRM`, en suivant
(et en affinant) la procedure documentee dans `hyprland-quickshell-sandbox.md`
a la racine de `workflow-claude/`.

But : eviter d'avoir a tout recompiler depuis zero (plusieurs heures, chaque
etape resolvant un manque de version au fil de l'eau) la prochaine fois
qu'un environnement de test Hyprland+Quickshell est necessaire dans un
sandbox similaire.

## Contenu

### Binaires (compiles pour Ubuntu 25.04 "Plucky", amd64, gcc-15/g++-15)

- `Hyprland` (22 Mo) — le compositeur, avec support config Lua.
- `hyprctl` — client IPC Hyprland.
- `quickshell` (11 Mo) — shell QML, compile avec `-DCRASH_HANDLER=OFF`.
- `screencopy` — client minimal `wlr-screencopy` (protocole
  `zwlr_screencopy_manager_v1`) pour capturer un vrai screenshot PNG d'un
  compositeur Hyprland/wlroots. `weston-screenshooter` NE fonctionne PAS
  (protocole different). Sources incluses (`screencopy.c`,
  `wlr-screencopy-unstable-v1*.{xml,c,h}`) pour recompiler si besoin sur une
  autre archi : `gcc -o screencopy screencopy.c
  wlr-screencopy-unstable-v1-client-protocol.c $(pkg-config --cflags --libs
  wayland-client libpng)`.

Ces binaires attendent les bibliotheques partagees ci-dessous installees
sous `/usr/lib/x86_64-linux-gnu/` (memes noms/versions) pour fonctionner —
sinon `error while loading shared libraries`.

### `hyprland-libs.tar.gz` (2 Mo compresse, 6 Mo decompresse)

Toutes les bibliotheques compilees depuis les sources (absentes ou trop
anciennes dans les depots Ubuntu au moment de la compilation) : hyprutils,
hyprlang, aquamarine, hyprcursor, hyprgraphics, hyprwire, libinput (1.32.0),
xkbcommon (1.13.2), Lua 5.5.1 — plus leurs fichiers `.pc` (pkg-config) et
en-tetes `.h`/`.hpp`, et les protocoles `hyprland-protocols`. A extraire a
la racine (`tar xzf hyprland-libs.tar.gz -C /`) DANS le chroot/systeme cible
puis `ldconfig`.

**Toujours installer via `apt` en premier** les paquets normaux de la
distribution cible (`libhyprutils-dev` etc.) : n'utiliser ce tarball QUE
pour les bibliotheques dont la version depot est trop ancienne (c'etait le
cas pour toutes celles listees ci-dessus au moment de cette compilation,
sur Ubuntu 25.04 "Plucky" — a revalider sur une distribution plus recente,
les depots evoluent).

### `lua5.5.pc`

Fichier pkg-config CORRECT pour Lua 5.5 compile depuis les sources (deja
inclus dans le tarball ci-dessus, present ici separement en reference).
**Piege rencontre** : un `.pc` sans champ `Description:` est silencieusement
ignore par `pkgconf` moderne (`pkg-config --debug` montre
"file does not declare a Description field" -> "skipping invalid file"),
sans qu'aucune erreur claire n'apparaisse autrement — `pkg-config --exists`
echoue juste en disant "package not found" comme si le fichier n'existait
pas du tout.

### `wayland-protocols_1.49-1_all.deb`

Ubuntu Plucky (25.04) ne fournit que `wayland-protocols` 1.41 (Hyprland en
exige >= 1.49), et le depot amont reel est sur `gitlab.freedesktop.org`
(bloque par la plupart des allowlists sandbox). Version 1.49 trouvee sous
forme de `.deb` pret a l'emploi directement dans le pool APT standard
d'Ubuntu (`archive.ubuntu.com/ubuntu/pool/main/w/wayland-protocols/`), donc
accessible meme avec un reseau restreint. Installer avec
`dpkg -i wayland-protocols_1.49-1_all.deb` (paquet `all`, independant de
l'architecture).

### `virtio-gpu.ko` / `virtio_dma_buf.ko`

Modules noyau pour le GPU virtio dans la VM QEMU (voir le guide principal),
deja extraits et decompresses (`.ko.zst` -> `.ko` via `unzstd`) pour la
version de noyau `linux-image-generic` d'Ubuntu 24.04 au moment de cette
session. **A revalider/re-extraire si la version du paquet
`linux-image-generic` a change** (les modules sont lies a une version de
noyau precise) — voir le guide principal, section 1.2, pour la commande
d'extraction.

### `patches/`

Deux correctifs de compatibilite stdlib C++23/26 (gcc-15 supporte la
syntaxe mais pas encore toute l'implementation de la bibliotheque standard
correspondante), a appliquer avec `git apply` juste apres le clone des
depots concernes. Voir `patches/README.md` pour le detail exact.

### `vmctl.py` / `run-vm.sh`

- `vmctl.py <commande> <secondes_attente>` : pilote la VM QEMU via son
  socket serie (`/tmp/vm-serial.sock`) sans terminal interactif — envoie
  une commande, attend, retourne toute la sortie accumulee. Utiliser une
  chaine vide comme commande pour juste lire la sortie en cours (utile
  pendant le boot).
- `run-vm.sh <rootdisk.img> <utildisk.img>` : lance QEMU avec les bons
  parametres (GPU virtio, les deux disques, socket serie) et rappelle la
  sequence de commandes a executer ensuite dans la VM (montages, chargement
  GPU, lancement Hyprland puis Quickshell, capture d'ecran).

## Ce qui N'EST PAS inclus (trop volumineux pour un repo git normal)

- L'image disque complete de la VM (`rootdisk.img`, ~3-4 Go) et le disque
  utilitaire (`utildisk.img`, 50 Mo) : a reconstruire selon le guide
  principal, en reutilisant les binaires/libs de ce dossier pour sauter la
  recompilation (installer ce tarball + ces binaires dans un chroot fraichement
  debootstrap plutot que de tout recompiler).
- Le noyau complet + initrd (`linux-image-generic`) : a reinstaller via
  `apt-get install linux-image-generic` sur l'hote au moment voulu (paquet
  standard, pas la peine de le committer ici).

## Contraintes rencontrees a documenter pour la prochaine fois

- **1 seul CPU** disponible dans le sandbox utilise pour cette session :
  chaque compilation (`ninja -j1`) prend plusieurs dizaines de minutes.
  Prevoir du temps.
- **Espace disque tres serre** (~9 Go disponibles au depart, jusqu'a moins
  de 3 Go de marge en cours de route) : nettoyer agressivement
  (`rm -rf build/`, `apt-get clean`, supprimer les sources deja installees)
  entre chaque etape. Utiliser `truncate` (fichier sparse) plutot que `dd
  if=/dev/zero` pour creer `rootdisk.img`, et prevoir une marge d'au moins
  500 Mo-1 Go de libre APRES le `rsync` du chroot vers l'image (sinon la VM
  ne peut plus rien ecrire du tout au runtime — sockets, logs, etc.).
- **Le conteneur sandbox peut redemarrer entre deux appels d'outils**,
  tuant tous les process en arriere-plan (QEMU inclus) meme lances avec
  `setsid` — mais **le systeme de fichiers persiste**. Toujours verifier
  `ps aux | grep qemu` avant de supposer que la VM tourne encore ; si elle a
  disparu, relancer `run-vm.sh` depuis les memes fichiers `.img` (pas besoin
  de tout refaire).
- **`rsync --exclude=/proc --exclude=/sys`** exclut aussi les DOSSIERS eux-
  memes (pas juste leur contenu) si la source les a — `mkdir -p /proc /sys`
  dans la VM avant de les monter, sinon `mount: mount point does not exist`.
- L'image disque ext4 (`rootdisk.img`) peut etre montee DIRECTEMENT sur
  l'hote (`mount -o loop rootdisk.img /mnt/...`) pour en extraire des
  fichiers sans repasser par QEMU/le socket serie — beaucoup plus rapide
  pour recuperer un binaire ou un log apres coup.
