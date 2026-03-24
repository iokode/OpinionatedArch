#!/usr/bin/env bash

chroot_configure_users_and_groups() {
  groupadd dotfiles
  groupadd login-users

  install -d -m 2775 -o root -g dotfiles /dotfiles
  install -d -m 2775 -o root -g dotfiles /dotfiles/config

  IFS=',' read -r -a login_users <<< "${LOGIN_USERS_CSV}"

  local user
  for user in "${login_users[@]}"; do
    useradd -M -d "/home/${user}" -G wheel,dotfiles,login-users -s /bin/bash "${user}"
    chown -R "${user}:${user}" "/home/${user}"
    printf '%s:%s\n' "${user}" "${SHARED_SECRET}" | chpasswd
  done

  passwd -l root

  cat > /etc/sudoers.d/10-wheel <<'SUDO_EOF'
%wheel ALL=(ALL:ALL) ALL
SUDO_EOF
  chmod 440 /etc/sudoers.d/10-wheel
}
