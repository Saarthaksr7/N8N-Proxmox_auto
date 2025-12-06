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

function perform_backup {
  local BACKUP_PATH
  local DIR
  local DIR_DASH
  local BACKUP_FILE
  local selected_directories=()

  BACKUP_PATH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "\nDefaults to /root/\ne.g. /mnt/backups/" 11 68 --title "Directory to backup to:" 3>&1 1>&2 2>&3) || return

  BACKUP_PATH="${BACKUP_PATH:-/root/}"

  DIR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "\nDefaults to /etc/\ne.g. /root/, /var/lib/pve-cluster/ etc." 11 68 --title "Directory to work in:" 3>&1 1>&2 2>&3) || return

  DIR="${DIR:-/etc/}"

  DIR_DASH=$(echo "$DIR" | tr '/' '-')
  BACKUP_FILE="$(hostname)${DIR_DASH}backup"

  local CTID_MENU=()
  while read -r dir; do
    CTID_MENU+=("$(basename "$dir")" "$dir " "OFF")
  done < <(ls -d "${DIR}"*)

  local HOST_BACKUP
  while [ -z "${HOST_BACKUP:+x}" ]; do
    HOST_BACKUP=$(whiptail --backtitle "Proxmox VE Host Backup" --title "Working in the ${DIR} directory " --checklist \
      "\nSelect what files/directories to backup:\n" 16 $(((${#DIRNAME} + 2) + 88)) 6 "${CTID_MENU[@]}" 3>&1 1>&2 2>&3) || return

    for selected_dir in ${HOST_BACKUP//\"/}; do
      selected_directories+=("${DIR}$selected_dir")
    done
  done

  header_info
  echo -e "This will create a backup in\e[1;33m $BACKUP_PATH \e[0mfor these files and directories\e[1;33m ${selected_directories[*]} \e[0m"
  read -p "Press ENTER to continue..."
  header_info
  echo "Working..."
  tar -czf "$BACKUP_PATH$BACKUP_FILE-$(date +%Y_%m_%d).tar.gz" --absolute-names "${selected_directories[@]}"
  header_info
  echo -e "\nFinished"
  echo -e "\e[1;33m \nA backup is rendered ineffective when it remains stored on the host.\n \e[0m"
  sleep 2
}

while true; do
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE Host Backup" --yesno "This will create backups for particular files and directories located within a designated directory. Proceed?" 10 88); then
    perform_backup
  else
    break
  fi
done


