#!/usr/bin/env bash

chroot_plymouth_escape_string() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

chroot_plymouth_write_text() {
  local script_file="$1"
  local name="$2"
  local text="$3"
  local x="$4"
  local y="$5"
  local red="$6"
  local green="$7"
  local blue="$8"
  local escaped=""

  escaped="$(chroot_plymouth_escape_string "${text}")"
  printf '%s_image = Image.Text("%s", %s, %s, %s, 1.0, theme_font);\n' "${name}" "${escaped}" "${red}" "${green}" "${blue}" >> "${script_file}"
  printf '%s_sprite = Sprite(%s_image);\n' "${name}" "${name}" >> "${script_file}"
  printf '%s_sprite.SetPosition(%s, %s, 10);\n' "${name}" "${x}" "${y}" >> "${script_file}"
}

chroot_plymouth_write_box() {
  local script_file="$1"
  local name="$2"
  local x="$3"
  local y="$4"
  local width="$5"
  local height="$6"
  local image_file="$7"

  printf '%s_image = Image("%s").Scale(%s, %s);\n' "${name}" "${image_file}" "${width}" "${height}" >> "${script_file}"
  printf '%s_sprite = Sprite(%s_image);\n' "${name}" "${name}" >> "${script_file}"
  printf '%s_sprite.SetPosition(%s, %s, 8);\n' "${name}" "${x}" "${y}" >> "${script_file}"
}

chroot_plymouth_render_template() {
  local language_code="$1"
  local block_index="$2"
  local block_x="$3"
  local block_y="$4"
  local block_width="$5"
  local block_height="$6"
  local wrap_width="$7"
  local box_image="$8"
  local template_file="/usr/opinionatedarch/assets/returning-templates/${language_code}.tpl"
  local language_name=""
  local message_text=""
  local line=""
  local line_number=0
  local wrapped_line=""
  local rendered_line=""
  local line_index=0

  [[ -f "${template_file}" ]] || die "Return-message template not found in chroot: ${template_file}"

  while IFS= read -r line || [[ -n "${line}" ]]; do
    ((line_number += 1))
    if (( line_number == 1 )); then
      language_name="${line}"
    elif (( line_number >= 3 )); then
      if [[ -n "${message_text}" ]]; then
        message_text+=$'\n'
      fi
      message_text+="${line}"
    fi
  done < "${template_file}"

  message_text="${message_text//\{\{OWNER_NAME\}\}/${OWNER_NAME}}"
  message_text="${message_text//\{\{OWNER_PHONE\}\}/${OWNER_PHONE}}"
  message_text="${message_text//\{\{OWNER_EMAIL\}\}/${OWNER_EMAIL}}"
  message_text="${message_text//\{\{OWNER_RETURN_ADDRESS\}\}/${OWNER_RETURN_ADDRESS}}"

  chroot_plymouth_write_box "/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script" "box_${block_index}" "${block_x} + 8" "${block_y} + 8" "${block_width} - 16" "${block_height} - 16" "${box_image}"
  chroot_plymouth_write_text "/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script" "title_${block_index}_base" "${language_name}" "${block_x} + 24" "${block_y} + 18" "0.72" "0.84" "1.0"
  chroot_plymouth_write_text "/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script" "title_${block_index}_bold" "${language_name}" "${block_x} + 25" "${block_y} + 18" "0.72" "0.84" "1.0"

  while IFS= read -r wrapped_line || [[ -n "${wrapped_line}" ]]; do
    while IFS= read -r rendered_line || [[ -n "${rendered_line}" ]]; do
      chroot_plymouth_write_text "/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script" "message_${block_index}_${line_index}" "${rendered_line}" "${block_x} + 24" "${block_y} + 58 + (${line_index} * 24)" "1.0" "1.0" "1.0"
      ((line_index += 1))
    done < <(printf '%s\n' "${wrapped_line}" | LC_ALL=C.UTF-8 fold -s -w "${wrap_width}")
  done <<< "${message_text}"
}

chroot_plymouth_render_language_blocks() {
  local script_file="/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script"
  local -a languages=()
  local language_count=0

  IFS=',' read -r -a languages <<< "${RETURN_MESSAGE_LANGUAGES_CSV}"
  language_count="${#languages[@]}"
  (( language_count >= 1 && language_count <= 4 )) || die "Return-message theme requires between 1 and 4 languages."

  cat >> "${script_file}" <<'PLYMOUTH_LAYOUT_EOF'
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
content_x = 80;
content_y = 150;
content_width = screen_width - 160;
box_gap = 24;
password_box_height = 62;
password_box_y = screen_height - 136;
password_text_y = password_box_y + 20;
content_height = password_box_y - content_y + 8 - box_gap;
column_gap = box_gap - 16;
row_gap = box_gap - 16;
column_width = (content_width - column_gap) / 2;
half_height = (content_height - row_gap) / 2;
right_column_x = content_x + column_width + column_gap;
bottom_row_y = content_y + half_height + row_gap;
PLYMOUTH_LAYOUT_EOF

  if (( language_count == 1 )); then
    chroot_plymouth_render_template "${languages[0]}" 1 "content_x" "content_y" "content_width" "content_height" 76 "box-full.png"
  elif (( language_count == 2 )); then
    chroot_plymouth_render_template "${languages[0]}" 1 "content_x" "content_y" "content_width" "half_height" 76 "box-half.png"
    chroot_plymouth_render_template "${languages[1]}" 2 "content_x" "bottom_row_y" "content_width" "half_height" 76 "box-half.png"
  elif (( language_count == 3 )); then
    chroot_plymouth_render_template "${languages[0]}" 1 "content_x" "content_y" "content_width" "half_height" 76 "box-half.png"
    chroot_plymouth_render_template "${languages[1]}" 2 "content_x" "bottom_row_y" "column_width" "half_height" 34 "box-quarter.png"
    chroot_plymouth_render_template "${languages[2]}" 3 "right_column_x" "bottom_row_y" "column_width" "half_height" 34 "box-quarter.png"
  else
    chroot_plymouth_render_template "${languages[0]}" 1 "content_x" "content_y" "column_width" "half_height" 55 "box-quarter.png"
    chroot_plymouth_render_template "${languages[1]}" 2 "right_column_x" "content_y" "column_width" "half_height" 55 "box-quarter.png"
    chroot_plymouth_render_template "${languages[2]}" 3 "content_x" "bottom_row_y" "column_width" "half_height" 55 "box-quarter.png"
    chroot_plymouth_render_template "${languages[3]}" 4 "right_column_x" "bottom_row_y" "column_width" "half_height" 55 "box-quarter.png"
  fi
}

chroot_configure_plymouth_defaults() {
  local plymouth_font=""
  local escaped_plymouth_font=""

  if [[ "${INCLUDE_RETURN_MESSAGE}" != "yes" ]]; then
    return 0
  fi

  install -d -m 755 /etc/opinionatedarch
  install -d -m 755 /etc/initcpio/hooks
  install -d -m 755 /etc/initcpio/install
  install -d -m 755 /usr/share/plymouth/themes/opinionatedarch
  install -d -m 755 /usr/share/fonts/opinionatedarch

  cat > /etc/opinionatedarch/ownership.env <<OWNERSHIP_EOF
OWNER_NAME=${OWNER_NAME}
OWNER_PHONE=${OWNER_PHONE}
OWNER_EMAIL=${OWNER_EMAIL}
OWNER_RETURN_ADDRESS=${OWNER_RETURN_ADDRESS}
INCLUDE_LOGO=${INCLUDE_LOGO}
RETURN_MESSAGE_LANGUAGES_CSV=${RETURN_MESSAGE_LANGUAGES_CSV}
OWNERSHIP_EOF

  cp /usr/opinionatedarch/assets/initcpio/hooks/opinionatedarch-plymouth-locale /etc/initcpio/hooks/opinionatedarch-plymouth-locale
  cp /usr/opinionatedarch/assets/initcpio/install/opinionatedarch-plymouth-locale /etc/initcpio/install/opinionatedarch-plymouth-locale
  cp /usr/opinionatedarch/assets/initcpio/install/opinionatedarch-plymouth-font /etc/initcpio/install/opinionatedarch-plymouth-font

  cp /usr/opinionatedarch/assets/plymouth/opinionatedarch/fonts/OpenSans.ttf /usr/share/fonts/opinionatedarch/OpenSans.ttf
  cp /usr/opinionatedarch/assets/plymouth/opinionatedarch/fonts/OFL.txt /usr/share/fonts/opinionatedarch/OpenSans-OFL.txt
  fc-cache -f /usr/share/fonts/opinionatedarch

  cp /usr/opinionatedarch/assets/plymouth/opinionatedarch/opinionatedarch.plymouth /usr/share/plymouth/themes/opinionatedarch/opinionatedarch.plymouth
  cp /usr/opinionatedarch/assets/plymouth/opinionatedarch/script-base.script /usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script
  plymouth_font="$(sed -n 's/^Font=//p' /usr/share/plymouth/themes/opinionatedarch/opinionatedarch.plymouth | head -n 1)"
  escaped_plymouth_font="$(chroot_plymouth_escape_string "${plymouth_font}")"
  printf 'theme_font = "%s";\n' "${escaped_plymouth_font}" >> /usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script
  cp /usr/opinionatedarch/assets/plymouth/opinionatedarch/box-full.png /usr/share/plymouth/themes/opinionatedarch/box-full.png
  cp /usr/opinionatedarch/assets/plymouth/opinionatedarch/box-half.png /usr/share/plymouth/themes/opinionatedarch/box-half.png
  cp /usr/opinionatedarch/assets/plymouth/opinionatedarch/box-quarter.png /usr/share/plymouth/themes/opinionatedarch/box-quarter.png
  cp /usr/opinionatedarch/assets/plymouth/opinionatedarch/box-password.png /usr/share/plymouth/themes/opinionatedarch/box-password.png

  if [[ "${INCLUDE_LOGO}" == "yes" ]]; then
    cp /usr/opinionatedarch/tmp/logo.png /usr/share/plymouth/themes/opinionatedarch/logo.png
    cat /usr/opinionatedarch/assets/plymouth/opinionatedarch/script-logo.script >> /usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script
  fi

  chroot_plymouth_render_language_blocks

  cat /usr/opinionatedarch/assets/plymouth/opinionatedarch/script-password.script >> /usr/share/plymouth/themes/opinionatedarch/opinionatedarch.script

  plymouth-set-default-theme opinionatedarch
}
