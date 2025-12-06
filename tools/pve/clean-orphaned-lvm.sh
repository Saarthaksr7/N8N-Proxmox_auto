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

function find_orphaned_lvm {
    echo -e "\n🔍 Scanning for orphaned LVM volumes...\n"

    orphaned_volumes=()
    while read -r lv vg size; do
        if [[ "$lv" == "data" || "$lv" == "root" || "$lv" == "swap" || "$lv" =~ ^osd-block- ]]; then
            continue
        fi
        container_id=$(echo "$lv" | grep -oE "[0-9]+" | head -1)
        if [ -f "/etc/pve/lxc/${container_id}.conf" ] || [ -f "/etc/pve/qemu-server/${container_id}.conf" ]; then
            continue
        fi
        orphaned_volumes+=("$lv" "$vg" "$size")
    done < <(lvs --noheadings -o lv_name,vg_name,lv_size --separator ' ' | awk '{print $1, $2, $3}')

    echo -e "❗ The following orphaned LVM volumes were found:\n"
    printf "%-25s %-10s %-10s\n" "LV Name" "VG" "Size"
    printf "%-25s %-10s %-10s\n" "-------------------------" "----------" "----------"

    for ((i = 0; i < ${#orphaned_volumes[@]}; i += 3)); do
        printf "%-25s %-10s %-10s\n" "${orphaned_volumes[i]}" "${orphaned_volumes[i + 1]}" "${orphaned_volumes[i + 2]}"
    done
    echo ""
}

function delete_orphaned_lvm {
    for ((i = 0; i < ${#orphaned_volumes[@]}; i += 3)); do
        lv="${orphaned_volumes[i]}"
        vg="${orphaned_volumes[i + 1]}"
        size="${orphaned_volumes[i + 2]}"

        read -p "❓ Do you want to delete $lv (VG: $vg, Size: $size)? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "🗑️  Deleting $lv from $vg..."
            lvremove -f "$vg/$lv"
            if [ $? -eq 0 ]; then
                echo -e "✅ Successfully deleted $lv.\n"
            else
                echo -e "❌ Failed to delete $lv.\n"
            fi
        else
            echo -e "⚠️  Skipping $lv.\n"
        fi
    done
}

header_info
find_orphaned_lvm
delete_orphaned_lvm

echo -e "✅ Cleanup process completed!\n"


