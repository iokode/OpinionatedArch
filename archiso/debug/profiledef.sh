#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# An image for trying a working tree in rather than for installing machines
# with. It boots UEFI only, which is all this project supports, and it is
# compressed to be built quickly rather than to be small.

iso_name="oparch-debug"
iso_label="OPARCH_DEBUG"
iso_publisher="OpinionatedArch <https://oparch.iokode.dev>"
iso_application="OpinionatedArch debug image"
iso_version="$(date +%Y.%m.%d.%H%M)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="erofs"
airootfs_image_tool_options=('-zlz4hc')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/bin/oparch-installer"]="0:0:755"
  ["/usr/bin/oparch-installer-interactive"]="0:0:755"
  ["/usr/bin/oparch-return-message-render"]="0:0:755"
  ["/usr/bin/oparch-dotfiles-sync"]="0:0:755"
  ["/usr/lib/oparch/oparch-installer-interactive"]="0:0:755"
  ["/usr/lib/oparch/libbaml_cffi-x86_64-unknown-linux-gnu.so"]="0:0:755"
)
