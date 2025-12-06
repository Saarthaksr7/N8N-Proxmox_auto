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

set -eEuo pipefail
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")

header_info
echo "Loading..."
NODE=$(hostname)

  echo -e "${BL}[Info]${GN} Update repository check is disabled in this local version.${CL}\n"
}

header_info
echo -e "${GN}Update check skipped.${CL}\n"


