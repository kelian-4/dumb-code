#!/usr/bin/env bash
# Sequence complete, testee et fonctionnelle, pour faire tourner Hyprland +
# Quickshell dans un conteneur sandbox sans GPU (voir le guide complet dans
# workflow-claude/README.md et le fichier de reference "hyprland-quickshell-sandbox.md").
#
# Prerequis avant de lancer ce script :
# - rootdisk.img et utildisk.img deja construits (voir le guide complet pour
#   les recreer si besoin depuis zero, ou reutiliser les binaires/libs de ce
#   dossier bin/ pour eviter de tout recompiler dans un nouveau chroot).
# - /boot/vmlinuz-<version> et /boot/initrd.img-<version> installes sur
#   l'hote (apt-get install linux-image-generic).
# - qemu-system-x86_64 installe sur l'hote.
#
# Usage : ./run-vm.sh /chemin/vers/rootdisk.img /chemin/vers/utildisk.img
set -euo pipefail

ROOTDISK="${1:?Usage: $0 <rootdisk.img> <utildisk.img>}"
UTILDISK="${2:?Usage: $0 <rootdisk.img> <utildisk.img>}"
KVER=$(ls /lib/modules/ | grep generic | head -1)
SOCK=/tmp/vm-serial.sock

rm -f "$SOCK"

setsid qemu-system-x86_64 \
  -kernel "/boot/vmlinuz-$KVER" \
  -initrd "/boot/initrd.img-$KVER" \
  -append "console=ttyS0 root=/dev/vda rw init=/bin/bash" \
  -device virtio-gpu-pci \
  -drive file="$ROOTDISK",format=raw,if=virtio \
  -drive file="$UTILDISK",format=raw,if=virtio \
  -m 2048 -smp 1 -nographic \
  -chardev socket,id=char0,path="$SOCK",server=on,wait=off \
  -serial chardev:char0 -monitor none -no-reboot < /dev/null > /tmp/qemu.log 2>&1 &

echo "QEMU lance (PID $!). Attendre ~15-20s le temps du boot, puis piloter"
echo "la VM avec vmctl.py, par exemple :"
echo ""
echo "  python3 vmctl.py \"\" 15    # attendre la fin du boot, voir le shell root"
echo ""
echo "Puis dans la VM (une seule commande vmctl.py, tout enchaine) :"
cat << 'INNER'

  mkdir -p /proc /sys /dev/pts /dev/shm /mnt/util /run/user/0
  mount -t proc proc /proc
  mount -t sysfs sysfs /sys
  mount -t devpts devpts /dev/pts
  mount -t tmpfs tmpfs /dev/shm
  mount /dev/vdb /mnt/util
  /mnt/util/busybox insmod /mnt/util/virtio_dma_buf.ko
  /mnt/util/busybox insmod /mnt/util/virtio-gpu.ko
  chmod 666 /dev/dri/card0 /dev/dri/renderD128
  export XDG_RUNTIME_DIR=/run/user/0 WLR_BACKENDS=headless
  (Hyprland --i-am-really-stupid > /tmp/hypr.log 2>&1 &)
  sleep 4 && ls /run/user/0/hypr/   # note la signature d'instance affichee

  # puis, avec la signature notee ci-dessus :
  export XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1 \
         QT_QUICK_BACKEND=software \
         HYPRLAND_INSTANCE_SIGNATURE=<signature notee ci-dessus>
  (quickshell -p /chemin/vers/shell.qml > /tmp/qs.log 2>&1 &)
  sleep 6

  # capturer un screenshot (binaire screencopy de ce dossier, deja copie
  # sur utildisk.img ou transfere via mount/umount du disque partage) :
  ./screencopy   # ecrit wayland-screenshot.png dans le repertoire courant

INNER
