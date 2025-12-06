#!/usr/bin/env bash






function header_info {
  clear
  cat <<"EOF"
   _____ _____ ______
  / ____|  __ \____  |
 | (___ | |__) |  / /
  \___ \|  _  /  / /
  ____) | | \ \ / /
 |_____/|_|  \_/_/
EOF
}
header_info
while true; do
  read -p "This will Prepare a LXC Container for Frigate. Proceed (y/n)?" yn
  case $yn in
  [Yy]*) break ;;
  [Nn]*) exit ;;
  *) echo "Please answer yes or no." ;;
  esac
done
header_info

CHAR_DEVS+=("1:1")     # mem
CHAR_DEVS+=("29:0")    # fb0
CHAR_DEVS+=("188:.*")  # ttyUSB*
CHAR_DEVS+=("189:.*")  # bus/usb/*
CHAR_DEVS+=("226:0")   # card0
CHAR_DEVS+=("226:128") # renderD128

for char_dev in ${CHAR_DEVS[@]}; do
  [ ! -z "${CHAR_DEV_STRING-}" ] && CHAR_DEV_STRING+=" -o"
  CHAR_DEV_STRING+=" -regex \".*/${char_dev}\""
done

read -r -d '' HOOK_SCRIPT <<-EOF || true
for char_dev in \$(find /sys/dev/char -regextype sed $CHAR_DEV_STRING); do
  dev="/dev/\$(sed -n "/DEVNAME/ s/^.*=\(.*\)$/\1/p" \${char_dev}/uevent)";
  mkdir -p \$(dirname \${LXC_ROOTFS_MOUNT}\${dev});
  for link in \$(udevadm info --query=property \$dev | sed -n "s/DEVLINKS=//p"); do
    mkdir -p \${LXC_ROOTFS_MOUNT}\$(dirname \$link);
    cp -dpR \$link \${LXC_ROOTFS_MOUNT}\${link};
  done;
  cp -dpR \$dev \${LXC_ROOTFS_MOUNT}\${dev};
done;
EOF

HOOK_SCRIPT=${HOOK_SCRIPT//$'\n'/}

NODE=$(hostname)
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  ITEM=$(echo "$line" | awk '{print substr($0,36)}')
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  CTID_MENU+=("$TAG" "$ITEM " "OFF")
done < <(pct list | awk 'NR>1')

while [ -z "${CTID:+x}" ]; do
  CTID=$(whiptail --backtitle "SR7" --title "Containers on $NODE" --radiolist \
    "\nSelect a container to add support:\n" \
    16 $(($MSG_MAX_LENGTH + 23)) 6 \
    "${CTID_MENU[@]}" 3>&1 1>&2 2>&3)
done

CTID_CONFIG_PATH=/etc/pve/lxc/${CTID}.conf
sed '/autodev/d' "$CTID_CONFIG_PATH" >CTID.conf
cat CTID.conf >"$CTID_CONFIG_PATH"

cat <<EOF >>"$CTID_CONFIG_PATH"
lxc.autodev: 1
lxc.hook.autodev: bash -c '$HOOK_SCRIPT'
EOF
echo -e "\e[1;33m \nFinished....Reboot ${CTID} LXC to apply the changes.\n \e[0m"




