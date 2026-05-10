#!/usr/bin/env bash

chroot_configure_snapshots() {
  install -m 755 /usr/opinionatedarch/bin/oparch-snapshot-system /usr/local/bin/oparch-snapshot-system
  install -m 755 /usr/opinionatedarch/bin/oparch-snapshot-home /usr/local/bin/oparch-snapshot-home
}
