#!/usr/bin/env bash

chroot_configure_network_stack() {
  systemctl enable NetworkManager.service
  systemctl enable systemd-resolved.service
}
