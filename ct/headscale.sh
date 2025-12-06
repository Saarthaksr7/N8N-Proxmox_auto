#!/usr/bin/env bash


post_to_api() {
  return 0
}

post_to_api_vm() {
  return 0
}

POST_UPDATE_DONE=false
post_update_to_api() {
  return 0
}

install_node_and_modules() {
  local NODE_VERSION="${NODE_VERSION:-22}"
  local NODE_MODULE="${NODE_MODULE:-}"
  local CURRENT_NODE_VERSION=""
  local NEED_NODE_INSTALL=false

  if command -v node >/dev/null; then
    CURRENT_NODE_VERSION="$(node -v | grep -oP '^v\K[0-9]+')"
    if [[ "$CURRENT_NODE_VERSION" != "$NODE_VERSION" ]]; then
      msg_info "Node.js version $CURRENT_NODE_VERSION found, replacing with $NODE_VERSION"
      NEED_NODE_INSTALL=true
    else
      msg_ok "Node.js $NODE_VERSION already installed"
    fi
  else
    msg_info "Node.js not found, installing version $NODE_VERSION"
    NEED_NODE_INSTALL=true
  fi

  if [[ "$NEED_NODE_INSTALL" == true ]]; then
    $STD apt-get purge -y nodejs
    rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg

    mkdir -p /etc/apt/keyrings

    if ! curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
      gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; then
      msg_error "Failed to download or import NodeSource GPG key"
      exit 1
    fi

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" \
      >/etc/apt/sources.list.d/nodesource.list

    if ! apt-get update >/dev/null 2>&1; then
      msg_error "Failed to update APT repositories after adding NodeSource"
      exit 1
    fi

    if ! apt-get install -y nodejs >/dev/null 2>&1; then
      msg_error "Failed to install Node.js ${NODE_VERSION} from NodeSource"
      exit 1
    fi

    msg_ok "Installed Node.js ${NODE_VERSION}"
  fi

  export NODE_OPTIONS="--max-old-space-size=4096"

  if [[ -n "$NODE_MODULE" ]]; then
    IFS=',' read -ra MODULES <<<"$NODE_MODULE"
    for mod in "${MODULES[@]}"; do
      local MODULE_NAME MODULE_REQ_VERSION MODULE_INSTALLED_VERSION
      if [[ "$mod" == *"@"* ]]; then
        MODULE_NAME="${mod%@*}"
        MODULE_REQ_VERSION="${mod#*@}"
      else
        MODULE_NAME="$mod"
        MODULE_REQ_VERSION="latest"
      fi

      if npm list -g --depth=0 "$MODULE_NAME" >/dev/null 2>&1; then
        MODULE_INSTALLED_VERSION="$(npm list -g --depth=0 "$MODULE_NAME" | grep "$MODULE_NAME@" | awk -F@ '{print $2}' | tr -d '[:space:]')"
        if [[ "$MODULE_REQ_VERSION" != "latest" && "$MODULE_REQ_VERSION" != "$MODULE_INSTALLED_VERSION" ]]; then
          msg_info "Updating $MODULE_NAME from v$MODULE_INSTALLED_VERSION to v$MODULE_REQ_VERSION"
          if ! $STD npm install -g "${MODULE_NAME}@${MODULE_REQ_VERSION}"; then
            msg_error "Failed to update $MODULE_NAME to version $MODULE_REQ_VERSION"
            exit 1
          fi
        elif [[ "$MODULE_REQ_VERSION" == "latest" ]]; then
          msg_info "Updating $MODULE_NAME to latest version"
          if ! $STD npm install -g "${MODULE_NAME}@latest"; then
            msg_error "Failed to update $MODULE_NAME to latest version"
            exit 1
          fi
        else
          msg_ok "$MODULE_NAME@$MODULE_INSTALLED_VERSION already installed"
        fi
      else
        msg_info "Installing $MODULE_NAME@$MODULE_REQ_VERSION"
        if ! $STD npm install -g "${MODULE_NAME}@${MODULE_REQ_VERSION}"; then
          msg_error "Failed to install $MODULE_NAME@$MODULE_REQ_VERSION"
          exit 1
        fi
      fi
    done
    msg_ok "All requested Node modules have been processed"
  fi
}

install_postgresql() {
  local PG_VERSION="${PG_VERSION:-16}"
  local CURRENT_PG_VERSION=""
  local DISTRO
  local NEED_PG_INSTALL=false
  DISTRO="$(awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release)"

  if command -v psql >/dev/null; then
    CURRENT_PG_VERSION="$(psql -V | grep -oP '\s\K[0-9]+(?=\.)')"
    if [[ "$CURRENT_PG_VERSION" != "$PG_VERSION" ]]; then
      msg_info "PostgreSQL Version $CURRENT_PG_VERSION found, replacing with $PG_VERSION"
      NEED_PG_INSTALL=true
    fi
  else
    msg_info "PostgreSQL not found, installing version $PG_VERSION"
    NEED_PG_INSTALL=true
  fi

  if [[ "$NEED_PG_INSTALL" == true ]]; then
    msg_info "Stopping PostgreSQL if running"
    systemctl stop postgresql >/dev/null 2>&1 || true

    msg_info "Removing conflicting PostgreSQL packages"
    $STD apt-get purge -y "postgresql*"
    rm -f /etc/apt/sources.list.d/pgdg.list /etc/apt/trusted.gpg.d/postgresql.gpg

    msg_info "Setting up PostgreSQL Repository"
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc |
      gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

    echo "deb https://apt.postgresql.org/pub/repos/apt ${DISTRO}-pgdg main" \
      >/etc/apt/sources.list.d/pgdg.list

    $STD apt-get update
    $STD apt-get install -y "postgresql-${PG_VERSION}"

    msg_ok "Installed PostgreSQL ${PG_VERSION}"
  fi
}

install_mariadb() {
  local MARIADB_VERSION="${MARIADB_VERSION:-latest}"
  local DISTRO_CODENAME
  DISTRO_CODENAME="$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release)"

  if [[ "$MARIADB_VERSION" == "latest" ]]; then
    msg_info "Resolving latest MariaDB version"
    MARIADB_VERSION=$(curl -fsSL https://mariadb.org | grep -oP 'MariaDB \K10\.[0-9]+' | head -n1)
    if [[ -z "$MARIADB_VERSION" ]]; then
      msg_error "Could not determine latest MariaDB version"
      return 1
    fi
    msg_ok "Latest MariaDB version is $MARIADB_VERSION"
  fi

  local CURRENT_VERSION=""
  if command -v mariadb >/dev/null; then
    CURRENT_VERSION="$(mariadb --version | grep -oP 'Ver\s+\K[0-9]+\.[0-9]+')"
  fi

  if [[ "$CURRENT_VERSION" == "$MARIADB_VERSION" ]]; then
    msg_info "MariaDB $MARIADB_VERSION already installed, checking for upgrade"
    $STD apt-get update
    $STD apt-get install --only-upgrade -y mariadb-server mariadb-client
    msg_ok "MariaDB $MARIADB_VERSION upgraded if applicable"
    return 0
  fi

  if [[ -n "$CURRENT_VERSION" ]]; then
    msg_info "Replacing MariaDB $CURRENT_VERSION with $MARIADB_VERSION (data will be preserved)"
    $STD systemctl stop mariadb >/dev/null 2>&1 || true
    $STD apt-get purge -y 'mariadb*' || true
    rm -f /etc/apt/sources.list.d/mariadb.list /etc/apt/trusted.gpg.d/mariadb.gpg
  else
    msg_info "Installing MariaDB $MARIADB_VERSION"
  fi

  msg_info "Setting up MariaDB Repository"
  curl -fsSL "https://mariadb.org/mariadb_release_signing_key.asc" |
    gpg --dearmor -o /etc/apt/trusted.gpg.d/mariadb.gpg

  echo "deb [signed-by=/etc/apt/trusted.gpg.d/mariadb.gpg] http://mirror.mariadb.org/repo/${MARIADB_VERSION}/debian ${DISTRO_CODENAME} main" \
    >/etc/apt/sources.list.d/mariadb.list

  $STD apt-get update
  $STD apt-get install -y mariadb-server mariadb-client

  msg_ok "Installed MariaDB $MARIADB_VERSION"
}

install_mysql() {
  local MYSQL_VERSION="${MYSQL_VERSION:-8.0}"
  local CURRENT_VERSION=""
  local NEED_INSTALL=false

  if command -v mysql >/dev/null; then
    CURRENT_VERSION="$(mysql --version | grep -oP 'Distrib\s+\K[0-9]+\.[0-9]+')"
    if [[ "$CURRENT_VERSION" != "$MYSQL_VERSION" ]]; then
      msg_info "MySQL $CURRENT_VERSION found, replacing with $MYSQL_VERSION"
      NEED_INSTALL=true
    else
      msg_ok "MySQL $MYSQL_VERSION already installed"
    fi
  else
    msg_info "MySQL not found, installing version $MYSQL_VERSION"
    NEED_INSTALL=true
  fi

  if [[ "$NEED_INSTALL" == true ]]; then
    msg_info "Removing conflicting MySQL packages"
    $STD systemctl stop mysql >/dev/null 2>&1 || true
    $STD apt-get purge -y 'mysql*'
    rm -f /etc/apt/sources.list.d/mysql.list /etc/apt/trusted.gpg.d/mysql.gpg

    msg_info "Setting up MySQL APT Repository"
    DISTRO_CODENAME="$(awk -F= '/VERSION_CODENAME/ { print $2 }' /etc/os-release)"
    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 | gpg --dearmor -o /etc/apt/trusted.gpg.d/mysql.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/mysql.gpg] https://repo.mysql.com/apt/debian/ ${DISTRO_CODENAME} mysql-${MYSQL_VERSION}" \
      >/etc/apt/sources.list.d/mysql.list

    $STD apt-get update
    $STD apt-get install -y mysql-server

    msg_ok "Installed MySQL $MYSQL_VERSION"
  fi
}

install_php() {
  local PHP_VERSION="${PHP_VERSION:-8.4}"
  local PHP_MODULE="${PHP_MODULE:-}"
  local PHP_APACHE="${PHP_APACHE:-NO}"
  local PHP_FPM="${PHP_FPM:-NO}"
  local DEFAULT_MODULES="bcmath,cli,curl,gd,intl,mbstring,opcache,readline,xml,zip"
  local COMBINED_MODULES

  local PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-512M}"
  local PHP_UPLOAD_MAX_FILESIZE="${PHP_UPLOAD_MAX_FILESIZE:-128M}"
  local PHP_POST_MAX_SIZE="${PHP_POST_MAX_SIZE:-128M}"
  local PHP_MAX_EXECUTION_TIME="${PHP_MAX_EXECUTION_TIME:-300}"

  if [[ -n "$PHP_MODULE" ]]; then
    COMBINED_MODULES="${DEFAULT_MODULES},${PHP_MODULE}"
  else
    COMBINED_MODULES="${DEFAULT_MODULES}"
  fi

  COMBINED_MODULES=$(echo "$COMBINED_MODULES" | tr ',' '\n' | awk '!seen[$0]++' | paste -sd, -)

  local CURRENT_PHP
  CURRENT_PHP=$(php -v 2>/dev/null | awk '/^PHP/{print $2}' | cut -d. -f1,2)

  if [[ "$CURRENT_PHP" != "$PHP_VERSION" ]]; then
    $STD echo "PHP $CURRENT_PHP detected, migrating to PHP $PHP_VERSION"
    if [[ ! -f /etc/apt/sources.list.d/php.list ]]; then
      $STD curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
      $STD dpkg -i /tmp/debsuryorg-archive-keyring.deb
      echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
        >/etc/apt/sources.list.d/php.list
      $STD apt-get update
    fi

    $STD apt-get purge -y "php${CURRENT_PHP//./}"* || true
  fi

  local MODULE_LIST="php${PHP_VERSION}"
  IFS=',' read -ra MODULES <<<"$COMBINED_MODULES"
  for mod in "${MODULES[@]}"; do
    MODULE_LIST+=" php${PHP_VERSION}-${mod}"
  done

  if [[ "$PHP_APACHE" == "YES" ]]; then
    if [[ -f /etc/apache2/mods-enabled/php${CURRENT_PHP}.load ]]; then
      $STD a2dismod php${CURRENT_PHP} || true
    fi
  fi

  if [[ "$PHP_FPM" == "YES" ]]; then
    $STD systemctl stop php${CURRENT_PHP}-fpm || true
    $STD systemctl disable php${CURRENT_PHP}-fpm || true
  fi

  $STD apt-get install -y $MODULE_LIST
  msg_ok "Installed PHP $PHP_VERSION with selected modules"

  if [[ "$PHP_APACHE" == "YES" ]]; then
    $STD systemctl restart apache2 || true
  fi

  if [[ "$PHP_FPM" == "YES" ]]; then
    $STD systemctl enable php${PHP_VERSION}-fpm
    $STD systemctl restart php${PHP_VERSION}-fpm
  fi

  local PHP_INI_PATHS=()
  PHP_INI_PATHS+=("/etc/php/${PHP_VERSION}/cli/php.ini")
  [[ "$PHP_FPM" == "YES" ]] && PHP_INI_PATHS+=("/etc/php/${PHP_VERSION}/fpm/php.ini")
  [[ "$PHP_APACHE" == "YES" ]] && PHP_INI_PATHS+=("/etc/php/${PHP_VERSION}/apache2/php.ini")

  for ini in "${PHP_INI_PATHS[@]}"; do
    if [[ -f "$ini" ]]; then
      msg_info "Patching $ini"
      sed -i "s|^memory_limit = .*|memory_limit = ${PHP_MEMORY_LIMIT}|" "$ini"
      sed -i "s|^upload_max_filesize = .*|upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}|" "$ini"
      sed -i "s|^post_max_size = .*|post_max_size = ${PHP_POST_MAX_SIZE}|" "$ini"
      sed -i "s|^max_execution_time = .*|max_execution_time = ${PHP_MAX_EXECUTION_TIME}|" "$ini"
      msg_ok "Patched $ini"
    fi
  done
}

install_composer() {
  local COMPOSER_BIN="/usr/local/bin/composer"
  export COMPOSER_ALLOW_SUPERUSER=1

  if [[ -x "$COMPOSER_BIN" ]]; then
    local CURRENT_VERSION
    CURRENT_VERSION=$("$COMPOSER_BIN" --version | awk '{print $3}')
    msg_info "Composer $CURRENT_VERSION found, updating to latest"
  else
    msg_info "Composer not found, installing latest version"
  fi

  curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1

  if [[ $? -ne 0 ]]; then
    msg_error "Failed to install Composer"
    return 1
  fi

  chmod +x "$COMPOSER_BIN"
  msg_ok "Installed Composer $($COMPOSER_BIN --version | awk '{print $3}')"
}

install_go() {
  local ARCH
  case "$(uname -m)" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    msg_error "Unsupported architecture: $(uname -m)"
    return 1
    ;;
  esac

  if [[ -z "${GO_VERSION:-}" || "${GO_VERSION}" == "latest" ]]; then
    GO_VERSION=$(curl -fsSL https://go.dev/VERSION?m=text | head -n1 | sed 's/^go//')
    if [[ -z "$GO_VERSION" ]]; then
      msg_error "Could not determine latest Go version"
      return 1
    fi
    msg_info "Detected latest Go version: $GO_VERSION"
  fi

  local GO_BIN="/usr/local/bin/go"
  local GO_INSTALL_DIR="/usr/local/go"

  if [[ -x "$GO_BIN" ]]; then
    local CURRENT_VERSION
    CURRENT_VERSION=$("$GO_BIN" version | awk '{print $3}' | sed 's/go//')
    if [[ "$CURRENT_VERSION" == "$GO_VERSION" ]]; then
      msg_ok "Go $GO_VERSION already installed"
      return 0
    else
      msg_info "Go $CURRENT_VERSION found, upgrading to $GO_VERSION"
      rm -rf "$GO_INSTALL_DIR"
    fi
  else
    msg_info "Installing Go $GO_VERSION"
  fi

  local TARBALL="go${GO_VERSION}.linux-${ARCH}.tar.gz"
  local URL="https://go.dev/dl/${TARBALL}"
  local TMP_TAR=$(mktemp)

  curl -fsSL "$URL" -o "$TMP_TAR" || {
    msg_error "Failed to download $TARBALL"
    return 1
  }

  tar -C /usr/local -xzf "$TMP_TAR"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -f "$TMP_TAR"

  msg_ok "Installed Go $GO_VERSION"
}

install_java() {
  local JAVA_VERSION="${JAVA_VERSION:-21}"
  local DISTRO_CODENAME
  DISTRO_CODENAME=$(awk -F= '/VERSION_CODENAME/ { print $2 }' /etc/os-release)
  local DESIRED_PACKAGE="temurin-${JAVA_VERSION}-jdk"

  if [[ ! -f /etc/apt/sources.list.d/adoptium.list ]]; then
    msg_info "Setting up Adoptium Repository"
    mkdir -p /etc/apt/keyrings
    curl -fsSL "https://packages.adoptium.net/artifactory/api/gpg/key/public" | gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${DISTRO_CODENAME} main" \
      >/etc/apt/sources.list.d/adoptium.list
    $STD apt-get update
    msg_ok "Set up Adoptium Repository"
  fi

  local INSTALLED_VERSION=""
  if dpkg -l | grep -q "temurin-.*-jdk"; then
    INSTALLED_VERSION=$(dpkg -l | awk '/temurin-.*-jdk/{print $2}' | grep -oP 'temurin-\K[0-9]+')
  fi

  if [[ "$INSTALLED_VERSION" == "$JAVA_VERSION" ]]; then
    msg_info "Temurin JDK $JAVA_VERSION already installed, updating if needed"
    $STD apt-get update
    $STD apt-get install --only-upgrade -y "$DESIRED_PACKAGE"
    msg_ok "Updated Temurin JDK $JAVA_VERSION (if applicable)"
  else
    if [[ -n "$INSTALLED_VERSION" ]]; then
      msg_info "Removing Temurin JDK $INSTALLED_VERSION"
      $STD apt-get purge -y "temurin-${INSTALLED_VERSION}-jdk"
    fi

    msg_info "Installing Temurin JDK $JAVA_VERSION"
    $STD apt-get install -y "$DESIRED_PACKAGE"
    msg_ok "Installed Temurin JDK $JAVA_VERSION"
  fi
}

install_mongodb() {
  local MONGO_VERSION="${MONGO_VERSION:-8.0}"
  local DISTRO_CODENAME
  DISTRO_CODENAME=$(awk -F= '/VERSION_CODENAME/ { print $2 }' /etc/os-release)
  local REPO_LIST="/etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list"

  local INSTALLED_VERSION=""
  if command -v mongod >/dev/null; then
    INSTALLED_VERSION=$(mongod --version | awk '/db version/{print $3}' | cut -d. -f1,2)
  fi

  if [[ "$INSTALLED_VERSION" == "$MONGO_VERSION" ]]; then
    msg_info "MongoDB $MONGO_VERSION already installed, checking for upgrade"
    $STD apt-get update
    $STD apt-get install --only-upgrade -y mongodb-org
    msg_ok "MongoDB $MONGO_VERSION upgraded if needed"
    return 0
  fi

  if [[ -n "$INSTALLED_VERSION" ]]; then
    msg_info "Replacing MongoDB $INSTALLED_VERSION with $MONGO_VERSION (data will be preserved)"
    $STD systemctl stop mongod || true
    $STD apt-get purge -y mongodb-org || true
    rm -f /etc/apt/sources.list.d/mongodb-org-*.list
    rm -f /etc/apt/trusted.gpg.d/mongodb-*.gpg
  else
    msg_info "Installing MongoDB $MONGO_VERSION"
  fi

  curl -fsSL "https://pgp.mongodb.com/server-${MONGO_VERSION}.asc" | gpg --dearmor -o "/etc/apt/trusted.gpg.d/mongodb-${MONGO_VERSION}.gpg"
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/mongodb-${MONGO_VERSION}.gpg] https://repo.mongodb.org/apt/debian ${DISTRO_CODENAME}/mongodb-org/${MONGO_VERSION} main" \
    >"$REPO_LIST"

  $STD apt-get update
  $STD apt-get install -y mongodb-org

  mkdir -p /var/lib/mongodb
  chown -R mongodb:mongodb /var/lib/mongodb

  $STD systemctl enable mongod
  $STD systemctl start mongod
  msg_ok "MongoDB $MONGO_VERSION installed and started"
}

fetch_and_deploy_gh_release() {
  local repo="$1"
  local app=$(echo ${APPLICATION,,} | tr -d ' ')
  local api_url="https://api.github.com/repos/$repo/releases/latest"
  local header=()
  local attempt=0
  local max_attempts=3
  local api_response tag http_code
  local current_version=""
  local curl_timeout="--connect-timeout 10 --max-time 30"

  if [[ -f "/opt/${app}_version.txt" ]]; then
    current_version=$(cat "/opt/${app}_version.txt")
    $STD msg_info "Current version: $current_version"
  fi

  if ! command -v jq &>/dev/null; then
    $STD msg_info "Installing jq..."
    $STD apt-get update -qq &>/dev/null
    $STD apt-get install -y jq &>/dev/null || {
      msg_error "Failed to install jq"
      return 1
    }
  fi

  [[ -n "${GITHUB_TOKEN:-}" ]] && header=(-H "Authorization: token $GITHUB_TOKEN")

  until [[ $attempt -ge $max_attempts ]]; do
    ((attempt++)) || true
    $STD msg_info "[$attempt/$max_attempts] Fetching GitHub release for $repo...\n"

    api_response=$(curl $curl_timeout -fsSL -w "%{http_code}" -o /tmp/gh_resp.json "${header[@]}" "$api_url")
    http_code="${api_response:(-3)}"

    if [[ "$http_code" == "404" ]]; then
      msg_error "Repository $repo has no Release candidate (404)"
      return 1
    fi

    if [[ "$http_code" != "200" ]]; then
      $STD msg_info "Request failed with HTTP $http_code, retrying...\n"
      sleep $((attempt * 2))
      continue
    fi

    api_response=$(</tmp/gh_resp.json)

    if echo "$api_response" | grep -q "API rate limit exceeded"; then
      msg_error "GitHub API rate limit exceeded."
      return 1
    fi

    if echo "$api_response" | jq -e '.message == "Not Found"' &>/dev/null; then
      msg_error "Repository not found: $repo"
      return 1
    fi

    tag=$(echo "$api_response" | jq -r '.tag_name // .name // empty')
    [[ "$tag" =~ ^v[0-9] ]] && tag="${tag:1}"

    if [[ -z "$tag" ]]; then
      $STD msg_info "Empty tag received, retrying...\n"
      sleep $((attempt * 2))
      continue
    fi

    $STD msg_ok "Found release: $tag for $repo"
    break
  done

  if [[ -z "$tag" ]]; then
    msg_error "Failed to fetch release for $repo after $max_attempts attempts."
    exit 1
  fi

  if [[ "$current_version" == "$tag" ]]; then
    $STD msg_info "Already running the latest version ($tag). Skipping update."
    return 0
  fi

  local version="$tag"
  local base_url="https://github.com/$repo/releases/download/v$tag"
  local tmpdir
  tmpdir=$(mktemp -d) || return 1

  local assets urls
  assets=$(echo "$api_response" | jq -r '.assets[].browser_download_url') || true

  local arch
  if command -v dpkg &>/dev/null; then
    arch=$(dpkg --print-architecture)
  elif command -v uname &>/dev/null; then
    case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    armv7l) arch="armv7" ;;
    armv6l) arch="armv6" ;;
    *) arch="unknown" ;;
    esac
  else
    arch="unknown"
  fi
  $STD msg_info "Detected system architecture: $arch"

  local url=""
  for u in $assets; do
    if [[ "$u" =~ $arch.*\.tar\.gz$ ]]; then
      url="$u"
      $STD msg_info "Found matching architecture asset: $url"
      break
    fi
  done

  if [[ -z "$url" ]]; then
    for u in $assets; do
      if [[ "$u" =~ (x86_64|amd64|arm64|armv7|armv6).*\.tar\.gz$ ]]; then
        url="$u"
        $STD msg_info "Architecture-specific asset not found, using: $url"
        break
      fi
    done
  fi

  if [[ -z "$url" ]]; then
    for u in $assets; do
      if [[ "$u" =~ \.tar\.gz$ ]]; then
        url="$u"
        $STD msg_info "Using generic tarball: $url"
        break
      fi
    done
  fi

  if [[ -z "$url" ]]; then
    url="https://github.com/$repo/archive/refs/tags/$version.tar.gz"
    $STD msg_info "Trying GitHub source tarball fallback: $url"
  fi

  local filename="${url##*/}"
  $STD msg_info "Downloading $url"

  if ! curl $curl_timeout -fsSL -o "$tmpdir/$filename" "$url"; then
    msg_error "Failed to download release asset from $url"
    rm -rf "$tmpdir"
    return 1
  fi

  mkdir -p "/opt/$app"

  tar -xzf "$tmpdir/$filename" -C "$tmpdir"
  local content_root
  content_root=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d)
  if [[ $(echo "$content_root" | wc -l) -eq 1 ]]; then
    cp -r "$content_root"/* "/opt/$app/"
  else
    cp -r "$tmpdir"/* "/opt/$app/"
  fi

  echo "$version" >"/opt/${app}_version.txt"
  $STD msg_ok "Deployed $app v$version to /opt/$app"
  rm -rf "$tmpdir"
}

  install_local_ip() {
  local BASE_DIR="/usr/local/ip-management"
  local SCRIPT_PATH="$BASE_DIR/update_local_ip.sh"
  local IP_FILE="/run/local-ip.env"
  local DISPATCHER_SCRIPT="/etc/networkd-dispatcher/routable.d/10-update-local-ip.sh"

  mkdir -p "$BASE_DIR"

  if ! dpkg -s networkd-dispatcher >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -yq networkd-dispatcher
  fi

  cat <<'EOF' >"$SCRIPT_PATH"
#!/bin/bash
set -euo pipefail

IP_FILE="/run/local-ip.env"
mkdir -p "$(dirname "$IP_FILE")"

get_current_ip() {
    local targets=("8.8.8.8" "1.1.1.1" "192.168.1.1" "10.0.0.1" "172.16.0.1" "default")
    local ip

    for target in "${targets[@]}"; do
        if [[ "$target" == "default" ]]; then
            ip=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
        else
            ip=$(ip route get "$target" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
        fi
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    done

    return 1
}

current_ip="$(get_current_ip)"

if [[ -z "$current_ip" ]]; then
    echo "[ERROR] Could not detect local IP" >&2
    exit 1
fi

if [[ -f "$IP_FILE" ]]; then
    source "$IP_FILE"
    [[ "$LOCAL_IP" == "$current_ip" ]] && exit 0
fi

echo "LOCAL_IP=$current_ip" > "$IP_FILE"
echo "[INFO] LOCAL_IP updated to $current_ip"
EOF

  chmod +x "$SCRIPT_PATH"

  mkdir -p "$(dirname "$DISPATCHER_SCRIPT")"
  cat <<EOF >"$DISPATCHER_SCRIPT"
#!/bin/bash
$SCRIPT_PATH
EOF

  chmod +x "$DISPATCHER_SCRIPT"
  systemctl enable --now networkd-dispatcher.service

  $STD msg_ok "LOCAL_IP helper installed using networkd-dispatcher"
}

import_local_ip() {
  local IP_FILE="/run/local-ip.env"
  if [[ -f "$IP_FILE" ]]; then
    source "$IP_FILE"
  fi

  if [[ -z "${LOCAL_IP:-}" ]]; then
    get_current_ip() {
      local targets=("8.8.8.8" "1.1.1.1" "192.168.1.1" "10.0.0.1" "172.16.0.1" "default")
      local ip

      for target in "${targets[@]}"; do
        if [[ "$target" == "default" ]]; then
          ip=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
        else
          ip=$(ip route get "$target" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
        fi
        if [[ -n "$ip" ]]; then
          echo "$ip"
          return 0
        fi
      done

      return 1
    }

    LOCAL_IP="$(get_current_ip || true)"
    if [[ -z "$LOCAL_IP" ]]; then
      msg_error "Could not determine LOCAL_IP"
      return 1
    fi
  fi

  export LOCAL_IP
}

function download_with_progress() {
  local url="$1"
  local output="$2"
  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then kill "$SPINNER_PID" >/dev/null; fi

  if ! command -v pv &>/dev/null; then
    $STD apt-get install -y pv
  fi
  set -o pipefail

  local content_length
  content_length=$(curl -fsSLI "$url" | awk '/Content-Length/ {print $2}' | tr -d '\r' || true)

  if [[ -z "$content_length" ]]; then
    if ! curl -fL# -o "$output" "$url"; then
      msg_error "Download failed"
      return 1
    fi
  else
    if ! curl -fsSL "$url" | pv -s "$content_length" >"$output"; then
      msg_error "Download failed"
      return 1
    fi
  fi
}

function setup_uv() {
  $STD msg_info "Checking uv installation..."
  UV_BIN="/usr/local/bin/uv"
  TMP_DIR=$(mktemp -d)
  ARCH=$(uname -m)

  if [[ "$ARCH" == "x86_64" ]]; then
    UV_TAR="uv-x86_64-unknown-linux-gnu.tar.gz"
  elif [[ "$ARCH" == "aarch64" ]]; then
    UV_TAR="uv-aarch64-unknown-linux-gnu.tar.gz"
  else
    msg_error "Unsupported architecture: $ARCH"
    rm -rf "$TMP_DIR"
    return 1
  fi

  LATEST_VERSION=$(curl -s https://api.github.com/repos/astral-sh/uv/releases/latest | grep '"tag_name":' | cut -d '"' -f4 | sed 's/^v//')
  if [[ -z "$LATEST_VERSION" ]]; then
    msg_error "Could not fetch latest uv version from GitHub."
    rm -rf "$TMP_DIR"
    return 1
  fi

  if [[ -x "$UV_BIN" ]]; then
    INSTALLED_VERSION=$($UV_BIN -V | awk '{print $2}')
    if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
      $STD msg_ok "uv is already at the latest version ($INSTALLED_VERSION)"
      rm -rf "$TMP_DIR"
      if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
        export PATH="/usr/local/bin:$PATH"
      fi
      return 0
    else
      $STD msg_info "Updating uv from $INSTALLED_VERSION to $LATEST_VERSION"
    fi
  else
    $STD msg_info "uv not found. Installing version $LATEST_VERSION"
  fi

  curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/${UV_TAR}" -o "$TMP_DIR/uv.tar.gz"
  tar -xzf "$TMP_DIR/uv.tar.gz" -C "$TMP_DIR"
  install -m 755 "$TMP_DIR"/*/uv "$UV_BIN"
  rm -rf "$TMP_DIR"

  ensure_usr_local_bin_persist
  msg_ok "uv installed/updated to $LATEST_VERSION"
}

function ensure_usr_local_bin_persist() {
  local PROFILE_FILE="/etc/profile.d/custom_path.sh"

  if [[ ! -f "$PROFILE_FILE" ]] && ! command -v pveversion &>/dev/null; then
    echo 'export PATH="/usr/local/bin:$PATH"' >"$PROFILE_FILE"
    chmod +x "$PROFILE_FILE"
  fi
}

function setup_gs() {
  msg_info "Setup Ghostscript"
  mkdir -p /tmp
  TMP_DIR=$(mktemp -d)
  CURRENT_VERSION=$(gs --version 2>/dev/null || echo "0")

  RELEASE_JSON=$(curl -fsSL https://api.github.com/repos/ArtifexSoftware/ghostpdl-downloads/releases/latest)
  LATEST_VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name":' | head -n1 | cut -d '"' -f4 | sed 's/^gs//')
  LATEST_VERSION_DOTTED=$(echo "$RELEASE_JSON" | grep '"name":' | head -n1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')

  if [[ -z "$LATEST_VERSION" ]]; then
    msg_error "Could not determine latest Ghostscript version from GitHub."
    rm -rf "$TMP_DIR"
    return
  fi

  if dpkg --compare-versions "$CURRENT_VERSION" ge "$LATEST_VERSION_DOTTED"; then
    msg_ok "Ghostscript is already at version $CURRENT_VERSION"
    rm -rf "$TMP_DIR"
    return
  fi

  msg_info "Installing/Updating Ghostscript to $LATEST_VERSION_DOTTED"
  curl -fsSL "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs${LATEST_VERSION}/ghostscript-${LATEST_VERSION_DOTTED}.tar.gz" -o "$TMP_DIR/ghostscript.tar.gz"

  if ! tar -xzf "$TMP_DIR/ghostscript.tar.gz" -C "$TMP_DIR"; then
    msg_error "Failed to extract Ghostscript archive."
    rm -rf "$TMP_DIR"
    return
  fi

  cd "$TMP_DIR/ghostscript-${LATEST_VERSION_DOTTED}" || {
    msg_error "Failed to enter Ghostscript source directory."
    rm -rf "$TMP_DIR"
  }
  $STD apt-get install -y build-essential libpng-dev zlib1g-dev
  ./configure >/dev/null && make && sudo make install >/dev/null
  local EXIT_CODE=$?
  hash -r
  if [[ ! -x "$(command -v gs)" ]]; then
    if [[ -x /usr/local/bin/gs ]]; then
      ln -sf /usr/local/bin/gs /usr/bin/gs
    fi
  fi

  rm -rf "$TMP_DIR"

  if [[ $EXIT_CODE -eq 0 ]]; then
    msg_ok "Ghostscript installed/updated to version $LATEST_VERSION_DOTTED"
  else
    msg_error "Ghostscript installation failed"
  fi
}

API_FUNC_CONTENT='
post_to_api() {
  return 0
}

post_to_api_vm() {
  return 0
}

POST_UPDATE_DONE=false
post_update_to_api() {
  return 0
}
'
TOOLS_FUNC_CONTENT='#!/bin/bash
install_node_and_modules() {
  local NODE_VERSION="${NODE_VERSION:-22}"
  local NODE_MODULE="${NODE_MODULE:-}"
  local CURRENT_NODE_VERSION=""
  local NEED_NODE_INSTALL=false

  if command -v node >/dev/null; then
    CURRENT_NODE_VERSION="$(node -v | grep -oP '\''^v\K[0-9]+'\'')"
    if [[ "$CURRENT_NODE_VERSION" != "$NODE_VERSION" ]]; then
      msg_info "Node.js version $CURRENT_NODE_VERSION found, replacing with $NODE_VERSION"
      NEED_NODE_INSTALL=true
    else
      msg_ok "Node.js $NODE_VERSION already installed"
    fi
  else
    msg_info "Node.js not found, installing version $NODE_VERSION"
    NEED_NODE_INSTALL=true
  fi

  if [[ "$NEED_NODE_INSTALL" == true ]]; then
    $STD apt-get purge -y nodejs
    rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg

    mkdir -p /etc/apt/keyrings

    if ! curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
      gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; then
      msg_error "Failed to download or import NodeSource GPG key"
      exit 1
    fi

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" \
      >/etc/apt/sources.list.d/nodesource.list

    if ! apt-get update >/dev/null 2>&1; then
      msg_error "Failed to update APT repositories after adding NodeSource"
      exit 1
    fi

    if ! apt-get install -y nodejs >/dev/null 2>&1; then
      msg_error "Failed to install Node.js ${NODE_VERSION} from NodeSource"
      exit 1
    fi

    msg_ok "Installed Node.js ${NODE_VERSION}"
  fi

  export NODE_OPTIONS="--max-old-space-size=4096"

  if [[ -n "$NODE_MODULE" ]]; then
    IFS='\'','\'' read -ra MODULES <<<"$NODE_MODULE"
    for mod in "${MODULES[@]}"; do
      local MODULE_NAME MODULE_REQ_VERSION MODULE_INSTALLED_VERSION
      if [[ "$mod" == *"@"* ]]; then
        MODULE_NAME="${mod%@*}"
        MODULE_REQ_VERSION="${mod#*@}"
      else
        MODULE_NAME="$mod"
        MODULE_REQ_VERSION="latest"
      fi

      if npm list -g --depth=0 "$MODULE_NAME" >/dev/null 2>&1; then
        MODULE_INSTALLED_VERSION="$(npm list -g --depth=0 "$MODULE_NAME" | grep "$MODULE_NAME@" | awk -F@ '\''{print $2}'\'' | tr -d '\''[:space:]'\'')"
        if [[ "$MODULE_REQ_VERSION" != "latest" && "$MODULE_REQ_VERSION" != "$MODULE_INSTALLED_VERSION" ]]; then
          msg_info "Updating $MODULE_NAME from v$MODULE_INSTALLED_VERSION to v$MODULE_REQ_VERSION"
          if ! $STD npm install -g "${MODULE_NAME}@${MODULE_REQ_VERSION}"; then
            msg_error "Failed to update $MODULE_NAME to version $MODULE_REQ_VERSION"
            exit 1
          fi
        elif [[ "$MODULE_REQ_VERSION" == "latest" ]]; then
          msg_info "Updating $MODULE_NAME to latest version"
          if ! $STD npm install -g "${MODULE_NAME}@latest"; then
            msg_error "Failed to update $MODULE_NAME to latest version"
            exit 1
          fi
        else
          msg_ok "$MODULE_NAME@$MODULE_INSTALLED_VERSION already installed"
        fi
      else
        msg_info "Installing $MODULE_NAME@$MODULE_REQ_VERSION"
        if ! $STD npm install -g "${MODULE_NAME}@${MODULE_REQ_VERSION}"; then
          msg_error "Failed to install $MODULE_NAME@$MODULE_REQ_VERSION"
          exit 1
        fi
      fi
    done
    msg_ok "All requested Node modules have been processed"
  fi
}

install_postgresql() {
  local PG_VERSION="${PG_VERSION:-16}"
  local CURRENT_PG_VERSION=""
  local DISTRO
  local NEED_PG_INSTALL=false
  DISTRO="$(awk -F'\''='\'' '\''/^VERSION_CODENAME=/{ print $NF }'\'' /etc/os-release)"

  if command -v psql >/dev/null; then
    CURRENT_PG_VERSION="$(psql -V | grep -oP '\''\s\K[0-9]+(?=\.)'\'')"
    if [[ "$CURRENT_PG_VERSION" != "$PG_VERSION" ]]; then
      msg_info "PostgreSQL Version $CURRENT_PG_VERSION found, replacing with $PG_VERSION"
      NEED_PG_INSTALL=true
    fi
  else
    msg_info "PostgreSQL not found, installing version $PG_VERSION"
    NEED_PG_INSTALL=true
  fi

  if [[ "$NEED_PG_INSTALL" == true ]]; then
    msg_info "Stopping PostgreSQL if running"
    systemctl stop postgresql >/dev/null 2>&1 || true

    msg_info "Removing conflicting PostgreSQL packages"
    $STD apt-get purge -y "postgresql*"
    rm -f /etc/apt/sources.list.d/pgdg.list /etc/apt/trusted.gpg.d/postgresql.gpg

    msg_info "Setting up PostgreSQL Repository"
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc |
      gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

    echo "deb https://apt.postgresql.org/pub/repos/apt ${DISTRO}-pgdg main" \
      >/etc/apt/sources.list.d/pgdg.list

    $STD apt-get update
    $STD apt-get install -y "postgresql-${PG_VERSION}"

    msg_ok "Installed PostgreSQL ${PG_VERSION}"
  fi
}

install_mariadb() {
  local MARIADB_VERSION="${MARIADB_VERSION:-latest}"
  local DISTRO_CODENAME
  DISTRO_CODENAME="$(awk -F= '\''/^VERSION_CODENAME=/{print $2}'\'' /etc/os-release)"

  if [[ "$MARIADB_VERSION" == "latest" ]]; then
    msg_info "Resolving latest MariaDB version"
    MARIADB_VERSION=$(curl -fsSL https://mariadb.org | grep -oP '\''MariaDB \K10\.[0-9]+'\'' | head -n1)
    if [[ -z "$MARIADB_VERSION" ]]; then
      msg_error "Could not determine latest MariaDB version"
      return 1
    fi
    msg_ok "Latest MariaDB version is $MARIADB_VERSION"
  fi

  local CURRENT_VERSION=""
  if command -v mariadb >/dev/null; then
    CURRENT_VERSION="$(mariadb --version | grep -oP '\''Ver\s+\K[0-9]+\.[0-9]+'\'')"
  fi

  if [[ "$CURRENT_VERSION" == "$MARIADB_VERSION" ]]; then
    msg_info "MariaDB $MARIADB_VERSION already installed, checking for upgrade"
    $STD apt-get update
    $STD apt-get install --only-upgrade -y mariadb-server mariadb-client
    msg_ok "MariaDB $MARIADB_VERSION upgraded if applicable"
    return 0
  fi

  if [[ -n "$CURRENT_VERSION" ]]; then
    msg_info "Replacing MariaDB $CURRENT_VERSION with $MARIADB_VERSION (data will be preserved)"
    $STD systemctl stop mariadb >/dev/null 2>&1 || true
    $STD apt-get purge -y '\''mariadb*'\'' || true
    rm -f /etc/apt/sources.list.d/mariadb.list /etc/apt/trusted.gpg.d/mariadb.gpg
  else
    msg_info "Installing MariaDB $MARIADB_VERSION"
  fi

  msg_info "Setting up MariaDB Repository"
  curl -fsSL "https://mariadb.org/mariadb_release_signing_key.asc" |
    gpg --dearmor -o /etc/apt/trusted.gpg.d/mariadb.gpg

  echo "deb [signed-by=/etc/apt/trusted.gpg.d/mariadb.gpg] http://mirror.mariadb.org/repo/${MARIADB_VERSION}/debian ${DISTRO_CODENAME} main" \
    >/etc/apt/sources.list.d/mariadb.list

  $STD apt-get update
  $STD apt-get install -y mariadb-server mariadb-client

  msg_ok "Installed MariaDB $MARIADB_VERSION"
}

install_mysql() {
  local MYSQL_VERSION="${MYSQL_VERSION:-8.0}"
  local CURRENT_VERSION=""
  local NEED_INSTALL=false

  if command -v mysql >/dev/null; then
    CURRENT_VERSION="$(mysql --version | grep -oP '\''Distrib\s+\K[0-9]+\.[0-9]+'\'')"
    if [[ "$CURRENT_VERSION" != "$MYSQL_VERSION" ]]; then
      msg_info "MySQL $CURRENT_VERSION found, replacing with $MYSQL_VERSION"
      NEED_INSTALL=true
    else
      msg_ok "MySQL $MYSQL_VERSION already installed"
    fi
  else
    msg_info "MySQL not found, installing version $MYSQL_VERSION"
    NEED_INSTALL=true
  fi

  if [[ "$NEED_INSTALL" == true ]]; then
    msg_info "Removing conflicting MySQL packages"
    $STD systemctl stop mysql >/dev/null 2>&1 || true
    $STD apt-get purge -y '\''mysql*'\''
    rm -f /etc/apt/sources.list.d/mysql.list /etc/apt/trusted.gpg.d/mysql.gpg

    msg_info "Setting up MySQL APT Repository"
    DISTRO_CODENAME="$(awk -F= '\''/VERSION_CODENAME/ { print $2 }'\'' /etc/os-release)"
    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 | gpg --dearmor -o /etc/apt/trusted.gpg.d/mysql.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/mysql.gpg] https://repo.mysql.com/apt/debian/ ${DISTRO_CODENAME} mysql-${MYSQL_VERSION}" \
      >/etc/apt/sources.list.d/mysql.list

    $STD apt-get update
    $STD apt-get install -y mysql-server

    msg_ok "Installed MySQL $MYSQL_VERSION"
  fi
}

install_php() {
  local PHP_VERSION="${PHP_VERSION:-8.4}"
  local PHP_MODULE="${PHP_MODULE:-}"
  local PHP_APACHE="${PHP_APACHE:-NO}"
  local PHP_FPM="${PHP_FPM:-NO}"
  local DEFAULT_MODULES="bcmath,cli,curl,gd,intl,mbstring,opcache,readline,xml,zip"
  local COMBINED_MODULES

  local PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-512M}"
  local PHP_UPLOAD_MAX_FILESIZE="${PHP_UPLOAD_MAX_FILESIZE:-128M}"
  local PHP_POST_MAX_SIZE="${PHP_POST_MAX_SIZE:-128M}"
  local PHP_MAX_EXECUTION_TIME="${PHP_MAX_EXECUTION_TIME:-300}"

  if [[ -n "$PHP_MODULE" ]]; then
    COMBINED_MODULES="${DEFAULT_MODULES},${PHP_MODULE}"
  else
    COMBINED_MODULES="${DEFAULT_MODULES}"
  fi

  COMBINED_MODULES=$(echo "$COMBINED_MODULES" | tr '\'','\'' '\''\n'\'' | awk '\''!seen[$0]++'\'' | paste -sd, -)

  local CURRENT_PHP
  CURRENT_PHP=$(php -v 2>/dev/null | awk '\''/^PHP/{print $2}'\'' | cut -d. -f1,2)

  if [[ "$CURRENT_PHP" != "$PHP_VERSION" ]]; then
    $STD echo "PHP $CURRENT_PHP detected, migrating to PHP $PHP_VERSION"
    if [[ ! -f /etc/apt/sources.list.d/php.list ]]; then
      $STD curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
      $STD dpkg -i /tmp/debsuryorg-archive-keyring.deb
      echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
        >/etc/apt/sources.list.d/php.list
      $STD apt-get update
    fi

    $STD apt-get purge -y "php${CURRENT_PHP//./}"* || true
  fi

  local MODULE_LIST="php${PHP_VERSION}"
  IFS='\'','\'' read -ra MODULES <<<"$COMBINED_MODULES"
  for mod in "${MODULES[@]}"; do
    MODULE_LIST+=" php${PHP_VERSION}-${mod}"
  done

  if [[ "$PHP_APACHE" == "YES" ]]; then
    if [[ -f /etc/apache2/mods-enabled/php${CURRENT_PHP}.load ]]; then
      $STD a2dismod php${CURRENT_PHP} || true
    fi
  fi

  if [[ "$PHP_FPM" == "YES" ]]; then
    $STD systemctl stop php${CURRENT_PHP}-fpm || true
    $STD systemctl disable php${CURRENT_PHP}-fpm || true
  fi

  $STD apt-get install -y $MODULE_LIST
  msg_ok "Installed PHP $PHP_VERSION with selected modules"

  if [[ "$PHP_APACHE" == "YES" ]]; then
    $STD systemctl restart apache2 || true
  fi

  if [[ "$PHP_FPM" == "YES" ]]; then
    $STD systemctl enable php${PHP_VERSION}-fpm
    $STD systemctl restart php${PHP_VERSION}-fpm
  fi

  local PHP_INI_PATHS=()
  PHP_INI_PATHS+=("/etc/php/${PHP_VERSION}/cli/php.ini")
  [[ "$PHP_FPM" == "YES" ]] && PHP_INI_PATHS+=("/etc/php/${PHP_VERSION}/fpm/php.ini")
  [[ "$PHP_APACHE" == "YES" ]] && PHP_INI_PATHS+=("/etc/php/${PHP_VERSION}/apache2/php.ini")

  for ini in "${PHP_INI_PATHS[@]}"; do
    if [[ -f "$ini" ]]; then
      msg_info "Patching $ini"
      sed -i "s|^memory_limit = .*|memory_limit = ${PHP_MEMORY_LIMIT}|" "$ini"
      sed -i "s|^upload_max_filesize = .*|upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}|" "$ini"
      sed -i "s|^post_max_size = .*|post_max_size = ${PHP_POST_MAX_SIZE}|" "$ini"
      sed -i "s|^max_execution_time = .*|max_execution_time = ${PHP_MAX_EXECUTION_TIME}|" "$ini"
      msg_ok "Patched $ini"
    fi
  done
}

install_composer() {
  local COMPOSER_BIN="/usr/local/bin/composer"
  export COMPOSER_ALLOW_SUPERUSER=1

  if [[ -x "$COMPOSER_BIN" ]]; then
    local CURRENT_VERSION
    CURRENT_VERSION=$("$COMPOSER_BIN" --version | awk '\''{print $3}'\'')
    msg_info "Composer $CURRENT_VERSION found, updating to latest"
  else
    msg_info "Composer not found, installing latest version"
  fi

  curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1

  if [[ $? -ne 0 ]]; then
    msg_error "Failed to install Composer"
    return 1
  fi

  chmod +x "$COMPOSER_BIN"
  msg_ok "Installed Composer $($COMPOSER_BIN --version | awk '\''{print $3}'\'')"
}

install_go() {
  local ARCH
  case "$(uname -m)" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    msg_error "Unsupported architecture: $(uname -m)"
    return 1
    ;;
  esac

  if [[ -z "${GO_VERSION:-}" || "${GO_VERSION}" == "latest" ]]; then
    GO_VERSION=$(curl -fsSL https://go.dev/VERSION?m=text | head -n1 | sed '\''s/^go//'\'')
    if [[ -z "$GO_VERSION" ]]; then
      msg_error "Could not determine latest Go version"
      return 1
    fi
    msg_info "Detected latest Go version: $GO_VERSION"
  fi

  local GO_BIN="/usr/local/bin/go"
  local GO_INSTALL_DIR="/usr/local/go"

  if [[ -x "$GO_BIN" ]]; then
    local CURRENT_VERSION
    CURRENT_VERSION=$("$GO_BIN" version | awk '\''{print $3}'\'' | sed '\''s/go//'\'')
    if [[ "$CURRENT_VERSION" == "$GO_VERSION" ]]; then
      msg_ok "Go $GO_VERSION already installed"
      return 0
    else
      msg_info "Go $CURRENT_VERSION found, upgrading to $GO_VERSION"
      rm -rf "$GO_INSTALL_DIR"
    fi
  else
    msg_info "Installing Go $GO_VERSION"
  fi

  local TARBALL="go${GO_VERSION}.linux-${ARCH}.tar.gz"
  local URL="https://go.dev/dl/${TARBALL}"
  local TMP_TAR=$(mktemp)

  curl -fsSL "$URL" -o "$TMP_TAR" || {
    msg_error "Failed to download $TARBALL"
    return 1
  }

  tar -C /usr/local -xzf "$TMP_TAR"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -f "$TMP_TAR"

  msg_ok "Installed Go $GO_VERSION"
}

install_java() {
  local JAVA_VERSION="${JAVA_VERSION:-21}"
  local DISTRO_CODENAME
  DISTRO_CODENAME=$(awk -F= '\''/VERSION_CODENAME/ { print $2 }'\'' /etc/os-release)
  local DESIRED_PACKAGE="temurin-${JAVA_VERSION}-jdk"

  if [[ ! -f /etc/apt/sources.list.d/adoptium.list ]]; then
    msg_info "Setting up Adoptium Repository"
    mkdir -p /etc/apt/keyrings
    curl -fsSL "https://packages.adoptium.net/artifactory/api/gpg/key/public" | gpg --dearmor -o /etc/apt/trusted.gpg.d/adoptium.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${DISTRO_CODENAME} main" \
      >/etc/apt/sources.list.d/adoptium.list
    $STD apt-get update
    msg_ok "Set up Adoptium Repository"
  fi

  local INSTALLED_VERSION=""
  if dpkg -l | grep -q "temurin-.*-jdk"; then
    INSTALLED_VERSION=$(dpkg -l | awk '\''/temurin-.*-jdk/{print $2}'\'' | grep -oP '\''temurin-\K[0-9]+'\'')
  fi

  if [[ "$INSTALLED_VERSION" == "$JAVA_VERSION" ]]; then
    msg_info "Temurin JDK $JAVA_VERSION already installed, updating if needed"
    $STD apt-get update
    $STD apt-get install --only-upgrade -y "$DESIRED_PACKAGE"
    msg_ok "Updated Temurin JDK $JAVA_VERSION (if applicable)"
  else
    if [[ -n "$INSTALLED_VERSION" ]]; then
      msg_info "Removing Temurin JDK $INSTALLED_VERSION"
      $STD apt-get purge -y "temurin-${INSTALLED_VERSION}-jdk"
    fi

    msg_info "Installing Temurin JDK $JAVA_VERSION"
    $STD apt-get install -y "$DESIRED_PACKAGE"
    msg_ok "Installed Temurin JDK $JAVA_VERSION"
  fi
}

install_mongodb() {
  local MONGO_VERSION="${MONGO_VERSION:-8.0}"
  local DISTRO_CODENAME
  DISTRO_CODENAME=$(awk -F= '\''/VERSION_CODENAME/ { print $2 }'\'' /etc/os-release)
  local REPO_LIST="/etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list"

  local INSTALLED_VERSION=""
  if command -v mongod >/dev/null; then
    INSTALLED_VERSION=$(mongod --version | awk '\''/db version/{print $3}'\'' | cut -d. -f1,2)
  fi

  if [[ "$INSTALLED_VERSION" == "$MONGO_VERSION" ]]; then
    msg_info "MongoDB $MONGO_VERSION already installed, checking for upgrade"
    $STD apt-get update
    $STD apt-get install --only-upgrade -y mongodb-org
    msg_ok "MongoDB $MONGO_VERSION upgraded if needed"
    return 0
  fi

  if [[ -n "$INSTALLED_VERSION" ]]; then
    msg_info "Replacing MongoDB $INSTALLED_VERSION with $MONGO_VERSION (data will be preserved)"
    $STD systemctl stop mongod || true
    $STD apt-get purge -y mongodb-org || true
    rm -f /etc/apt/sources.list.d/mongodb-org-*.list
    rm -f /etc/apt/trusted.gpg.d/mongodb-*.gpg
  else
    msg_info "Installing MongoDB $MONGO_VERSION"
  fi

  curl -fsSL "https://pgp.mongodb.com/server-${MONGO_VERSION}.asc" | gpg --dearmor -o "/etc/apt/trusted.gpg.d/mongodb-${MONGO_VERSION}.gpg"
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/mongodb-${MONGO_VERSION}.gpg] https://repo.mongodb.org/apt/debian ${DISTRO_CODENAME}/mongodb-org/${MONGO_VERSION} main" \
    >"$REPO_LIST"

  $STD apt-get update
  $STD apt-get install -y mongodb-org

  mkdir -p /var/lib/mongodb
  chown -R mongodb:mongodb /var/lib/mongodb

  $STD systemctl enable mongod
  $STD systemctl start mongod
  msg_ok "MongoDB $MONGO_VERSION installed and started"
}

fetch_and_deploy_gh_release() {
  local repo="$1"
  local app=$(echo ${APPLICATION,,} | tr -d '\'' '\'')
  local api_url="https://api.github.com/repos/$repo/releases/latest"
  local header=()
  local attempt=0
  local max_attempts=3
  local api_response tag http_code
  local current_version=""
  local curl_timeout="--connect-timeout 10 --max-time 30"

  if [[ -f "/opt/${app}_version.txt" ]]; then
    current_version=$(cat "/opt/${app}_version.txt")
    $STD msg_info "Current version: $current_version"
  fi

  if ! command -v jq &>/dev/null; then
    $STD msg_info "Installing jq..."
    $STD apt-get update -qq &>/dev/null
    $STD apt-get install -y jq &>/dev/null || {
      msg_error "Failed to install jq"
      return 1
    }
  fi

  [[ -n "${GITHUB_TOKEN:-}" ]] && header=(-H "Authorization: token $GITHUB_TOKEN")

  until [[ $attempt -ge $max_attempts ]]; do
    ((attempt++)) || true
    $STD msg_info "[$attempt/$max_attempts] Fetching GitHub release for $repo...\n"

    api_response=$(curl $curl_timeout -fsSL -w "%{http_code}" -o /tmp/gh_resp.json "${header[@]}" "$api_url")
    http_code="${api_response:(-3)}"

    if [[ "$http_code" == "404" ]]; then
      msg_error "Repository $repo has no Release candidate (404)"
      return 1
    fi

    if [[ "$http_code" != "200" ]]; then
      $STD msg_info "Request failed with HTTP $http_code, retrying...\n"
      sleep $((attempt * 2))
      continue
    fi

    api_response=$(</tmp/gh_resp.json)

    if echo "$api_response" | grep -q "API rate limit exceeded"; then
      msg_error "GitHub API rate limit exceeded."
      return 1
    fi

    if echo "$api_response" | jq -e '\''.message == "Not Found"'\'' &>/dev/null; then
      msg_error "Repository not found: $repo"
      return 1
    fi

    tag=$(echo "$api_response" | jq -r '\''.tag_name // .name // empty'\'')
    [[ "$tag" =~ ^v[0-9] ]] && tag="${tag:1}"

    if [[ -z "$tag" ]]; then
      $STD msg_info "Empty tag received, retrying...\n"
      sleep $((attempt * 2))
      continue
    fi

    $STD msg_ok "Found release: $tag for $repo"
    break
  done

  if [[ -z "$tag" ]]; then
    msg_error "Failed to fetch release for $repo after $max_attempts attempts."
    exit 1
  fi

  if [[ "$current_version" == "$tag" ]]; then
    $STD msg_info "Already running the latest version ($tag). Skipping update."
    return 0
  fi

  local version="$tag"
  local base_url="https://github.com/$repo/releases/download/v$tag"
  local tmpdir
  tmpdir=$(mktemp -d) || return 1

  local assets urls
  assets=$(echo "$api_response" | jq -r '\''.assets[].browser_download_url'\'') || true

  local arch
  if command -v dpkg &>/dev/null; then
    arch=$(dpkg --print-architecture)
  elif command -v uname &>/dev/null; then
    case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    armv7l) arch="armv7" ;;
    armv6l) arch="armv6" ;;
    *) arch="unknown" ;;
    esac
  else
    arch="unknown"
  fi
  $STD msg_info "Detected system architecture: $arch"

  local url=""
  for u in $assets; do
    if [[ "$u" =~ $arch.*\.tar\.gz$ ]]; then
      url="$u"
      $STD msg_info "Found matching architecture asset: $url"
      break
    fi
  done

  if [[ -z "$url" ]]; then
    for u in $assets; do
      if [[ "$u" =~ (x86_64|amd64|arm64|armv7|armv6).*\.tar\.gz$ ]]; then
        url="$u"
        $STD msg_info "Architecture-specific asset not found, using: $url"
        break
      fi
    done
  fi

  if [[ -z "$url" ]]; then
    for u in $assets; do
      if [[ "$u" =~ \.tar\.gz$ ]]; then
        url="$u"
        $STD msg_info "Using generic tarball: $url"
        break
      fi
    done
  fi

  if [[ -z "$url" ]]; then
    url="https://github.com/$repo/archive/refs/tags/$version.tar.gz"
    $STD msg_info "Trying GitHub source tarball fallback: $url"
  fi

  local filename="${url##*/}"
  $STD msg_info "Downloading $url"

  if ! curl $curl_timeout -fsSL -o "$tmpdir/$filename" "$url"; then
    msg_error "Failed to download release asset from $url"
    rm -rf "$tmpdir"
    return 1
  fi

  mkdir -p "/opt/$app"

  tar -xzf "$tmpdir/$filename" -C "$tmpdir"
  local content_root
  content_root=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d)
  if [[ $(echo "$content_root" | wc -l) -eq 1 ]]; then
    cp -r "$content_root"/* "/opt/$app/"
  else
    cp -r "$tmpdir"/* "/opt/$app/"
  fi

  echo "$version" >"/opt/${app}_version.txt"
  $STD msg_ok "Deployed $app v$version to /opt/$app"
  rm -rf "$tmpdir"
}

  install_local_ip() {
  local BASE_DIR="/usr/local/ip-management"
  local SCRIPT_PATH="$BASE_DIR/update_local_ip.sh"
  local IP_FILE="/run/local-ip.env"
  local DISPATCHER_SCRIPT="/etc/networkd-dispatcher/routable.d/10-update-local-ip.sh"

  mkdir -p "$BASE_DIR"

  if ! dpkg -s networkd-dispatcher >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -yq networkd-dispatcher
  fi

  cat <<'\''EOF'\'' >"$SCRIPT_PATH"
set -euo pipefail

IP_FILE="/run/local-ip.env"
mkdir -p "$(dirname "$IP_FILE")"

get_current_ip() {
    local targets=("8.8.8.8" "1.1.1.1" "192.168.1.1" "10.0.0.1" "172.16.0.1" "default")
    local ip

    for target in "${targets[@]}"; do
        if [[ "$target" == "default" ]]; then
            ip=$(ip route get 1 2>/dev/null | awk '\''{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'\'')
        else
            ip=$(ip route get "$target" 2>/dev/null | awk '\''{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'\'')
        fi
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    done

    return 1
}

current_ip="$(get_current_ip)"

if [[ -z "$current_ip" ]]; then
    echo "[ERROR] Could not detect local IP" >&2
    exit 1
fi

if [[ -f "$IP_FILE" ]]; then
    source "$IP_FILE"
    [[ "$LOCAL_IP" == "$current_ip" ]] && exit 0
fi

echo "LOCAL_IP=$current_ip" > "$IP_FILE"
echo "[INFO] LOCAL_IP updated to $current_ip"
EOF

  chmod +x "$SCRIPT_PATH"

  mkdir -p "$(dirname "$DISPATCHER_SCRIPT")"
  cat <<EOF >"$DISPATCHER_SCRIPT"
#!/bin/bash
$SCRIPT_PATH
EOF

  chmod +x "$DISPATCHER_SCRIPT"
  systemctl enable --now networkd-dispatcher.service

  $STD msg_ok "LOCAL_IP helper installed using networkd-dispatcher"
}

import_local_ip() {
  local IP_FILE="/run/local-ip.env"
  if [[ -f "$IP_FILE" ]]; then
    source "$IP_FILE"
  fi

  if [[ -z "${LOCAL_IP:-}" ]]; then
    get_current_ip() {
      local targets=("8.8.8.8" "1.1.1.1" "192.168.1.1" "10.0.0.1" "172.16.0.1" "default")
      local ip

      for target in "${targets[@]}"; do
        if [[ "$target" == "default" ]]; then
          ip=$(ip route get 1 2>/dev/null | awk '\''{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'\'')
        else
          ip=$(ip route get "$target" 2>/dev/null | awk '\''{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'\'')
        fi
        if [[ -n "$ip" ]]; then
          echo "$ip"
          return 0
        fi
      done

      return 1
    }

    LOCAL_IP="$(get_current_ip || true)"
    if [[ -z "$LOCAL_IP" ]]; then
      msg_error "Could not determine LOCAL_IP"
      return 1
    fi
  fi

  export LOCAL_IP
}

function download_with_progress() {
  local url="$1"
  local output="$2"
  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then kill "$SPINNER_PID" >/dev/null; fi

  if ! command -v pv &>/dev/null; then
    $STD apt-get install -y pv
  fi
  set -o pipefail

  local content_length
  content_length=$(curl -fsSLI "$url" | awk '\''/Content-Length/ {print $2}'\'' | tr -d '\''\r'\'' || true)

  if [[ -z "$content_length" ]]; then
    if ! curl -fL# -o "$output" "$url"; then
      msg_error "Download failed"
      return 1
    fi
  else
    if ! curl -fsSL "$url" | pv -s "$content_length" >"$output"; then
      msg_error "Download failed"
      return 1
    fi
  fi
}

function setup_uv() {
  $STD msg_info "Checking uv installation..."
  UV_BIN="/usr/local/bin/uv"
  TMP_DIR=$(mktemp -d)
  ARCH=$(uname -m)

  if [[ "$ARCH" == "x86_64" ]]; then
    UV_TAR="uv-x86_64-unknown-linux-gnu.tar.gz"
  elif [[ "$ARCH" == "aarch64" ]]; then
    UV_TAR="uv-aarch64-unknown-linux-gnu.tar.gz"
  else
    msg_error "Unsupported architecture: $ARCH"
    rm -rf "$TMP_DIR"
    return 1
  fi

  LATEST_VERSION=$(curl -s https://api.github.com/repos/astral-sh/uv/releases/latest | grep '\''"tag_name":'\'' | cut -d '\''"'\'' -f4 | sed '\''s/^v//'\'')
  if [[ -z "$LATEST_VERSION" ]]; then
    msg_error "Could not fetch latest uv version from GitHub."
    rm -rf "$TMP_DIR"
    return 1
  fi

  if [[ -x "$UV_BIN" ]]; then
    INSTALLED_VERSION=$($UV_BIN -V | awk '\''{print $2}'\'')
    if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
      $STD msg_ok "uv is already at the latest version ($INSTALLED_VERSION)"
      rm -rf "$TMP_DIR"
      if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
        export PATH="/usr/local/bin:$PATH"
      fi
      return 0
    else
      $STD msg_info "Updating uv from $INSTALLED_VERSION to $LATEST_VERSION"
    fi
  else
    $STD msg_info "uv not found. Installing version $LATEST_VERSION"
  fi

  curl -fsSL "https://github.com/astral-sh/uv/releases/latest/download/${UV_TAR}" -o "$TMP_DIR/uv.tar.gz"
  tar -xzf "$TMP_DIR/uv.tar.gz" -C "$TMP_DIR"
  install -m 755 "$TMP_DIR"/*/uv "$UV_BIN"
  rm -rf "$TMP_DIR"

  ensure_usr_local_bin_persist
  msg_ok "uv installed/updated to $LATEST_VERSION"
}

function ensure_usr_local_bin_persist() {
  local PROFILE_FILE="/etc/profile.d/custom_path.sh"

  if [[ ! -f "$PROFILE_FILE" ]] && ! command -v pveversion &>/dev/null; then
    echo '\''export PATH="/usr/local/bin:$PATH"'\'' >"$PROFILE_FILE"
    chmod +x "$PROFILE_FILE"
  fi
}

function setup_gs() {
  msg_info "Setup Ghostscript"
  mkdir -p /tmp
  TMP_DIR=$(mktemp -d)
  CURRENT_VERSION=$(gs --version 2>/dev/null || echo "0")

  RELEASE_JSON=$(curl -fsSL https://api.github.com/repos/ArtifexSoftware/ghostpdl-downloads/releases/latest)
  LATEST_VERSION=$(echo "$RELEASE_JSON" | grep '\''"tag_name":'\'' | head -n1 | cut -d '\''"'\'' -f4 | sed '\''s/^gs//'\'')
  LATEST_VERSION_DOTTED=$(echo "$RELEASE_JSON" | grep '\''"name":'\'' | head -n1 | grep -o '\''[0-9]\+\.[0-9]\+\.[0-9]\+'\'')

  if [[ -z "$LATEST_VERSION" ]]; then
    msg_error "Could not determine latest Ghostscript version from GitHub."
    rm -rf "$TMP_DIR"
    return
  fi

  if dpkg --compare-versions "$CURRENT_VERSION" ge "$LATEST_VERSION_DOTTED"; then
    msg_ok "Ghostscript is already at version $CURRENT_VERSION"
    rm -rf "$TMP_DIR"
    return
  fi

  msg_info "Installing/Updating Ghostscript to $LATEST_VERSION_DOTTED"
  curl -fsSL "https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs${LATEST_VERSION}/ghostscript-${LATEST_VERSION_DOTTED}.tar.gz" -o "$TMP_DIR/ghostscript.tar.gz"

  if ! tar -xzf "$TMP_DIR/ghostscript.tar.gz" -C "$TMP_DIR"; then
    msg_error "Failed to extract Ghostscript archive."
    rm -rf "$TMP_DIR"
    return
  fi

  cd "$TMP_DIR/ghostscript-${LATEST_VERSION_DOTTED}" || {
    msg_error "Failed to enter Ghostscript source directory."
    rm -rf "$TMP_DIR"
  }
  $STD apt-get install -y build-essential libpng-dev zlib1g-dev
  ./configure >/dev/null && make && sudo make install >/dev/null
  local EXIT_CODE=$?
  hash -r
  if [[ ! -x "$(command -v gs)" ]]; then
    if [[ -x /usr/local/bin/gs ]]; then
      ln -sf /usr/local/bin/gs /usr/bin/gs
    fi
  fi

  rm -rf "$TMP_DIR"

  if [[ $EXIT_CODE -eq 0 ]]; then
    msg_ok "Ghostscript installed/updated to version $LATEST_VERSION_DOTTED"
  else
    msg_error "Ghostscript installation failed"
  fi
}
'
INSTALL_FUNC_CONTENT='
color() {
  YW=$(echo "\033[33m")
  YWB=$(echo "\033[93m")
  BL=$(echo "\033[36m")
  RD=$(echo "\033[01;31m")
  GN=$(echo "\033[1;92m")

  CL=$(echo "\033[m")
  BFR="\\r\\033[K"
  BOLD=$(echo "\033[1m")
  HOLD=" "
  TAB="  "

  RETRY_NUM=10
  RETRY_EVERY=3

  CM="${TAB}✔️${TAB}${CL}"
  CROSS="${TAB}✖️${TAB}${CL}"
  INFO="${TAB}💡${TAB}${CL}"
  NETWORK="${TAB}📡${TAB}${CL}"
  OS="${TAB}🖥️${TAB}${CL}"
  OSVERSION="${TAB}🌟${TAB}${CL}"
  HOSTNAME="${TAB}🏠${TAB}${CL}"
  GATEWAY="${TAB}🌐${TAB}${CL}"
  DEFAULT="${TAB}⚙️${TAB}${CL}"
}

set_std_mode() {
  if [ "$VERBOSE" = "yes" ]; then
    STD=""
  else
    STD="silent"
  fi
}

silent() {
  "$@" >/dev/null 2>&1
}

verb_ip6() {
  set_std_mode # Set STD mode based on VERBOSE

  if [ "$DISABLEIPV6" == "yes" ]; then
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >>/etc/sysctl.conf
    $STD sysctl -p
  fi
}

catch_errors() {
  set -Eeuo pipefail
  trap '\''error_handler $LINENO "$BASH_COMMAND"'\'' ERR
}

error_handler() {

  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then kill "$SPINNER_PID" >/dev/null; fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message"
  if [[ "$line_number" -eq 50 ]]; then
    echo -e "The silent function has suppressed the error, run the script with verbose mode enabled, which will provide more detailed output.\n"
  else
  fi
}

spinner() {
  local frames=('\''⠋'\'' '\''⠙'\'' '\''⠹'\'' '\''⠸'\'' '\''⠼'\'' '\''⠴'\'' '\''⠦'\'' '\''⠧'\'' '\''⠇'\'' '\''⠏'\'')
  local spin_i=0
  local interval=0.1
  printf "\e[?25l"

  local color="${YWB}"

  while true; do
    printf "\r ${color}%s${CL}" "${frames[spin_i]}"
    spin_i=$(((spin_i + 1) % ${#frames[@]}))
    sleep "$interval"
  done
}

msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
  spinner &
  SPINNER_PID=$!
}

msg_ok() {
  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then kill "$SPINNER_PID" >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

msg_error() {
  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then kill "$SPINNER_PID" >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

setting_up_container() {
  msg_info "Setting up Container OS"
  sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
  locale_line=$(grep -v '\''^#'\'' /etc/locale.gen | grep -E '\''^[a-zA-Z]'\'' | awk '\''{print $1}'\'' | head -n 1)
  echo "LANG=${locale_line}" >/etc/default/locale
  locale-gen >/dev/null
  export LANG=${locale_line}
  echo "$tz" >/etc/timezone
  ln -sf /usr/share/zoneinfo/"$tz" /etc/localtime
  for ((i = RETRY_NUM; i > 0; i--)); do
    if [ "$(hostname -I)" != "" ]; then
      break
    fi
    echo 1>&2 -en "${CROSS}${RD} No Network! "
    sleep "$RETRY_EVERY"
  done
  if [ "$(hostname -I)" = "" ]; then
    echo 1>&2 -e "\n${CROSS}${RD} No Network After $RETRY_NUM Tries${CL}"
    echo -e "${NETWORK}Check Network Settings"
    exit 1
  fi
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  systemctl disable -q --now systemd-networkd-wait-online.service
  msg_ok "Set up Container OS"
  msg_ok "Network Connected: ${BL}$(hostname -I)"
}

network_check() {
  set +e
  trap - ERR
  ipv4_connected=false
  ipv6_connected=false
  sleep 1
  if ping -c 1 -W 1 1.1.1.1 &>/dev/null || ping -c 1 -W 1 8.8.8.8 &>/dev/null || ping -c 1 -W 1 9.9.9.9 &>/dev/null; then
    msg_ok "IPv4 Internet Connected"
    ipv4_connected=true
  else
    msg_error "IPv4 Internet Not Connected"
  fi

  if ping6 -c 1 -W 1 2606:4700:4700::1111 &>/dev/null || ping6 -c 1 -W 1 2001:4860:4860::8888 &>/dev/null || ping6 -c 1 -W 1 2620:fe::fe &>/dev/null; then
    msg_ok "IPv6 Internet Connected"
    ipv6_connected=true
  else
    msg_error "IPv6 Internet Not Connected"
  fi

  if [[ $ipv4_connected == false && $ipv6_connected == false ]]; then
    read -r -p "No Internet detected,would you like to continue anyway? <y/N> " prompt
    if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
      echo -e "${INFO}${RD}Expect Issues Without Internet${CL}"
    else
      echo -e "${NETWORK}Check Network Settings"
      exit 1
    fi
  fi

  RESOLVEDIP=$(getent hosts github.com | awk '\''{ print $1 }'\'')
  if [[ -z "$RESOLVEDIP" ]]; then msg_error "DNS Lookup Failure"; else msg_ok "DNS Resolved github.com to ${BL}$RESOLVEDIP${CL}"; fi
  set -e
  trap '\''error_handler $LINENO "$BASH_COMMAND"'\'' ERR
}

update_os() {
  msg_info "Updating Container OS"
  if [[ "$CACHER" == "yes" ]]; then
    echo "Acquire::http::Proxy-Auto-Detect \"/usr/local/bin/apt-proxy-detect.sh\";" >/etc/apt/apt.conf.d/00aptproxy
    cat <<EOF >/usr/local/bin/apt-proxy-detect.sh
#!/bin/bash
if nc -w1 -z "${CACHER_IP}" 3142; then
  echo -n "http://${CACHER_IP}:3142"
else
  echo -n "DIRECT"
fi
EOF
    chmod +x /usr/local/bin/apt-proxy-detect.sh
  fi
  $STD apt-get update
  $STD apt-get -o Dpkg::Options::="--force-confold" -y dist-upgrade
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  msg_ok "Updated Container OS"

  msg_info "Installing core dependencies"
  $STD apt-get update
  $STD apt-get install -y sudo curl mc gnupg2

  msg_ok "Core dependencies installed"
}

motd_ssh() {
  grep -qxF "export TERM='\''xterm-256color'\''" /root/.bashrc || echo "export TERM='\''xterm-256color'\''" >>/root/.bashrc

  if [ -f "/etc/os-release" ]; then
    OS_NAME=$(grep ^NAME /etc/os-release | cut -d= -f2 | tr -d '\''"'\'')
    OS_VERSION=$(grep ^VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '\''"'\'')
  elif [ -f "/etc/debian_version" ]; then
    OS_NAME="Debian"
    OS_VERSION=$(cat /etc/debian_version)
  fi

  PROFILE_FILE="/etc/profile.d/00_lxc-details.sh"
  echo "echo -e \"\"" >"$PROFILE_FILE"
  echo -e "echo -e \"${BOLD}${APPLICATION} LXC Container${CL}"\" >>"$PROFILE_FILE"

  echo "echo \"\"" >>"$PROFILE_FILE"
  echo -e "echo -e \"${TAB}${OS}${YW} OS: ${GN}${OS_NAME} - Version: ${OS_VERSION}${CL}\"" >>"$PROFILE_FILE"
  echo -e "echo -e \"${TAB}${HOSTNAME}${YW} Hostname: ${GN}\$(hostname)${CL}\"" >>"$PROFILE_FILE"
  echo -e "echo -e \"${TAB}${INFO}${YW} IP Address: ${GN}\$(hostname -I | awk '\''{print \$1}'\'')${CL}\"" >>"$PROFILE_FILE"

  chmod -x /etc/update-motd.d/*

  if [[ "${SSH_ROOT}" == "yes" ]]; then
    sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/g" /etc/ssh/sshd_config
    systemctl restart sshd
  fi
}

customize() {
  if [[ "$PASSWORD" == "" ]]; then
    msg_info "Customizing Container"
    GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
    mkdir -p $(dirname $GETTY_OVERRIDE)
    cat <<EOF >$GETTY_OVERRIDE
  [Service]
  ExecStart=
  ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
    systemctl daemon-reload
    systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed '\''s/\.d//'\'')
    msg_ok "Customized Container"
  fi

  if [[ -n "${SSH_AUTHORIZED_KEY}" ]]; then
    mkdir -p /root/.ssh
    echo "${SSH_AUTHORIZED_KEY}" >/root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
  fi
}
'
ALPINE_INSTALL_FUNC_CONTENT='# Copyright (c) 2021-2025 tteck

color() {
  YW=$(echo "\033[33m")
  BL=$(echo "\033[36m")
  RD=$(echo "\033[01;31m")
  GN=$(echo "\033[1;92m")

  CL=$(echo "\033[m")
  BFR="\\r\\033[K"
  BOLD=$(echo "\033[1m")
  TAB="  "

  RETRY_NUM=10
  RETRY_EVERY=3
  i=$RETRY_NUM

  CM="${TAB}✔️${TAB}${CL}"
  CROSS="${TAB}✖️${TAB}${CL}"
  INFO="${TAB}💡${TAB}${CL}"
  NETWORK="${TAB}📡${TAB}${CL}"
  OS="${TAB}🖥️${TAB}${CL}"
  HOSTNAME="${TAB}🏠${TAB}${CL}"
  GATEWAY="${TAB}🌐${TAB}${CL}"
}

set_std_mode() {
  if [ "$VERBOSE" = "yes" ]; then
    STD=""
  else
    STD="silent"
  fi
}

silent() {
  "$@" >/dev/null 2>&1
}

verb_ip6() {
  set_std_mode # Set STD mode based on VERBOSE

  if [ "$DISABLEIPV6" == "yes" ]; then
    $STD sysctl -w net.ipv6.conf.all.disable_ipv6=1
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >>/etc/sysctl.conf
    $STD rc-update add sysctl default
  fi
}

catch_errors() {
  set -Eeuo pipefail
  trap '\''error_handler $LINENO "$BASH_COMMAND"'\'' ERR
}

error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
}

msg_info() {
  local msg="$1"
  echo -ne " ${TAB}${YW}${msg}"
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

setting_up_container() {
  msg_info "Setting up Container OS"
  while [ "$i" -gt 0 ]; do
    if [ "$(ip addr show | grep '\''inet '\'' | grep -v '\''127.0.0.1'\'' | awk '\''{print $2}'\'' | cut -d'\''/'\'' -f1)" != "" ]; then
      break
    fi
    echo 1>&2 -en "${CROSS}${RD} No Network! "
    sleep "$RETRY_EVERY"
    i=$((i - 1))
  done

  if [ "$(ip addr show | grep '\''inet '\'' | grep -v '\''127.0.0.1'\'' | awk '\''{print $2}'\'' | cut -d'\''/'\'' -f1)" = "" ]; then
    echo 1>&2 -e "\n${CROSS}${RD} No Network After $RETRY_NUM Tries${CL}"
    echo -e "${NETWORK}Check Network Settings"
    exit 1
  fi
  msg_ok "Set up Container OS"
  msg_ok "Network Connected: ${BL}$(ip addr show | grep '\''inet '\'' | awk '\''{print $2}'\'' | cut -d'\''/'\'' -f1 | tail -n1)${CL}"
}

network_check() {
  set +e
  trap - ERR
  if ping -c 1 -W 1 1.1.1.1 &>/dev/null || ping -c 1 -W 1 8.8.8.8 &>/dev/null || ping -c 1 -W 1 9.9.9.9 &>/dev/null; then
    msg_ok "Internet Connected"
  else
    msg_error "Internet NOT Connected"
    read -r -p "Would you like to continue anyway? <y/N> " prompt
    if [[ "${prompt,,}" =~ ^(y|yes)$ ]]; then
      echo -e "${INFO}${RD}Expect Issues Without Internet${CL}"
    else
      echo -e "${NETWORK}Check Network Settings"
      exit 1
    fi
  fi
  RESOLVEDIP=$(getent hosts github.com | awk '\''{ print $1 }'\'')
  if [[ -z "$RESOLVEDIP" ]]; then msg_error "DNS Lookup Failure"; else msg_ok "DNS Resolved github.com to ${BL}$RESOLVEDIP${CL}"; fi
  set -e
  trap '\''error_handler $LINENO "$BASH_COMMAND"'\'' ERR
}

update_os() {
  msg_info "Updating Container OS"
  $STD apk update
  $STD apk upgrade
  msg_ok "Updated Container OS"

  msg_info "Installing core dependencies"
  $STD apk update
  $STD apk add newt curl openssh nano mc ncurses
  msg_ok "Core dependencies installed"
}

motd_ssh() {
  echo "export TERM='\''xterm-256color'\''" >>/root/.bashrc
  IP=$(ip -4 addr show eth0 | awk '\''/inet / {print $2}'\'' | cut -d/ -f1 | head -n 1)
  if [ -f "/etc/os-release" ]; then
    OS_NAME=$(grep ^NAME /etc/os-release | cut -d= -f2 | tr -d '\''"'\'')
    OS_VERSION=$(grep ^VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '\''"'\'')
  else
    OS_NAME="Alpine Linux"
    OS_VERSION="Unknown"
  fi

  PROFILE_FILE="/etc/profile.d/00_lxc-details.sh"
  echo "echo -e \"\"" >"$PROFILE_FILE"
  echo -e "echo -e \"${BOLD}${APPLICATION} LXC Container${CL}"\" >>"$PROFILE_FILE"

  echo "echo \"\"" >>"$PROFILE_FILE"
  echo -e "echo -e \"${TAB}${OS}${YW} OS: ${GN}${OS_NAME} - Version: ${OS_VERSION}${CL}\"" >>"$PROFILE_FILE"
  echo -e "echo -e \"${TAB}${HOSTNAME}${YW} Hostname: ${GN}\$(hostname)${CL}\"" >>"$PROFILE_FILE"
  echo -e "echo -e \"${TAB}${INFO}${YW} IP Address: ${GN}\$(ip -4 addr show eth0 | awk '\''/inet / {print \$2}'\'' | cut -d/ -f1 | head -n 1)${CL}\"" >>"$PROFILE_FILE"

  if [[ "${SSH_ROOT}" == "yes" ]]; then
    $STD rc-update add sshd
    sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/g" /etc/ssh/sshd_config
    $STD /etc/init.d/sshd start
  fi
}

validate_tz() {
  [[ -f "/usr/share/zoneinfo/$1" ]]
}

customize() {
  if [[ "$PASSWORD" == "" ]]; then
    msg_info "Customizing Container"
    bash -c "passwd -d root" >/dev/null 2>&1
    msg_ok "Customized Container"
  fi

}
'
INSTALL_SCRIPT_CONTENT='#!/usr/bin/env bash






source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

RELEASE=$(curl -fsSL https://api.github.com/repos/juanfont/headscale/releases/latest | grep "tag_name" | awk '\''{print substr($2, 3, length($2)-4) }'\'')
msg_info "Installing ${APPLICATION} v${RELEASE}"
curl -fsSL "https://github.com/juanfont/headscale/releases/download/v${RELEASE}/headscale_${RELEASE}_linux_amd64.deb" -o $(basename "https://github.com/juanfont/headscale/releases/download/v${RELEASE}/headscale_${RELEASE}_linux_amd64.deb")
$STD dpkg -i headscale_${RELEASE}_linux_amd64.deb
systemctl enable -q --now headscale
echo "${RELEASE}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed ${APPLICATION} v${RELEASE}"

motd_ssh
customize

msg_info "Cleaning up"
rm headscale_${RELEASE}_linux_amd64.deb
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

'

function create_lxc() {







YW=$(echo "\033[33m")
YWB=$(echo "\033[93m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")

CL=$(echo "\033[m")
UL=$(echo "\033[4m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"

set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

function error_handler() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  exit 200
}

function spinner() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spin_i=0
  local interval=0.1
  printf "\e[?25l"

  local color="${YWB}"

  while true; do
    printf "\r ${color}%s${CL}" "${frames[spin_i]}"
    spin_i=$(((spin_i + 1) % ${#frames[@]}))
    sleep "$interval"
  done
}

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
  spinner &
  SPINNER_PID=$!
}

function msg_warn() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${INFO}${YWB}${msg}${CL}"
}

function msg_ok() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

msg_info "Validating Storage"
VALIDCT=$(pvesm status -content rootdir | awk 'NR>1')
if [ -z "$VALIDCT" ]; then
  msg_error "Unable to detect a valid Container Storage location."
  exit 1
fi
VALIDTMP=$(pvesm status -content vztmpl | awk 'NR>1')
if [ -z "$VALIDTMP" ]; then
  msg_error "Unable to detect a valid Template Storage location."
  exit 1
fi

function select_storage() {
  local CLASS=$1
  local CONTENT
  local CONTENT_LABEL
  case $CLASS in
  container)
    CONTENT='rootdir'
    CONTENT_LABEL='Container'
    ;;
  template)
    CONTENT='vztmpl'
    CONTENT_LABEL='Container template'
    ;;
  *) false || {
    msg_error "Invalid storage class."
    exit 201
  } ;;
  esac

  local -a MENU
  while read -r line; do
    local TAG=$(echo $line | awk '{print $1}')
    local TYPE=$(echo $line | awk '{printf "%-10s", $2}')
    local FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
    local ITEM="Type: $TYPE Free: $FREE "
    local OFFSET=2
    if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
      local MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
    fi
    MENU+=("$TAG" "$ITEM" "OFF")
  done < <(pvesm status -content $CONTENT | awk 'NR>1')

  if [ $((${#MENU[@]} / 3)) -eq 1 ]; then
    printf ${MENU[0]}
  else
    local STORAGE
    while [ -z "${STORAGE:+x}" ]; do
      STORAGE=$(whiptail --backtitle "SR7" --title "Storage Pools" --radiolist \
        "Which storage pool would you like to use for the ${CONTENT_LABEL,,}?\nTo make a selection, use the Spacebar.\n" \
        16 $(($MSG_MAX_LENGTH + 23)) 6 \
        "${MENU[@]}" 3>&1 1>&2 2>&3) || {
        msg_error "Menu aborted."
        exit 202
      }
      if [ $? -ne 0 ]; then
        echo -e "${CROSS}${RD} Menu aborted by user.${CL}"
        exit 0
      fi
    done
    printf "%s" "$STORAGE"
  fi
}
[[ "${CTID:-}" ]] || {
  msg_error "You need to set 'CTID' variable."
  exit 203
}
[[ "${PCT_OSTYPE:-}" ]] || {
  msg_error "You need to set 'PCT_OSTYPE' variable."
  exit 204
}

[ "$CTID" -ge "100" ] || {
  msg_error "ID cannot be less than 100."
  exit 205
}


if qm status "$CTID" &>/dev/null || pct status "$CTID" &>/dev/null; then
  echo -e "ID '$CTID' is already in use."
  unset CTID
  msg_error "Cannot use ID that is already in use."
  exit 206
fi

TEMPLATE_STORAGE=$(select_storage template)
msg_ok "Using ${BL}$TEMPLATE_STORAGE${CL} ${GN}for Template Storage."

CONTAINER_STORAGE=$(select_storage container)
msg_ok "Using ${BL}$CONTAINER_STORAGE${CL} ${GN}for Container Storage."

msg_info "Updating LXC Template List"
pveam update >/dev/null
msg_ok "Updated LXC Template List"

TEMPLATE_SEARCH=${PCT_OSTYPE}-${PCT_OSVERSION:-}
mapfile -t TEMPLATES < <(pveam available -section system | sed -n "s/.*\($TEMPLATE_SEARCH.*\)/\1/p" | sort -t - -k 2 -V)
[ ${#TEMPLATES[@]} -gt 0 ] || {
  msg_error "Unable to find a template when searching for '$TEMPLATE_SEARCH'."
  exit 207
}
TEMPLATE="${TEMPLATES[-1]}"
TEMPLATE_PATH="$(pvesm path $TEMPLATE_STORAGE:vztmpl/$TEMPLATE)"
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE" || ! zstdcat "$TEMPLATE_PATH" | tar -tf - >/dev/null 2>&1; then
  msg_warn "Template $TEMPLATE not found in storage or seems to be corrupted. Redownloading."
  [[ -f "$TEMPLATE_PATH" ]] && rm -f "$TEMPLATE_PATH"

  for attempt in {1..3}; do
    msg_info "Attempt $attempt: Downloading LXC template..."

    if timeout 120 pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null; then
      msg_ok "Template download successful."
      break
    fi

    if [ $attempt -eq 3 ]; then
      msg_error "Three failed attempts. Aborting."
      exit 208
    fi

    sleep $((attempt * 5))
  done
fi
msg_ok "LXC Template is ready to use."

grep -q "root:100000:65536" /etc/subuid || echo "root:100000:65536" >>/etc/subuid
grep -q "root:100000:65536" /etc/subgid || echo "root:100000:65536" >>/etc/subgid

PCT_OPTIONS=(${PCT_OPTIONS[@]:-${DEFAULT_PCT_OPTIONS[@]}})
[[ " ${PCT_OPTIONS[@]} " =~ " -rootfs " ]] || PCT_OPTIONS+=(-rootfs "$CONTAINER_STORAGE:${PCT_DISK_SIZE:-8}")

msg_info "Creating LXC Container"
if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" &>/dev/null; then
  msg_error "Container creation failed. Checking if template is corrupted."

  if ! zstdcat "$TEMPLATE_PATH" | tar -tf - >/dev/null 2>&1; then
    msg_error "Template appears to be corrupted. Removing and re-downloading."
    rm -f "$TEMPLATE_PATH"

    if ! timeout 120 pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null; then
      msg_error "Failed to re-download template."
      exit 208
    fi

    msg_ok "Re-downloaded LXC Template"

    if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" &>/dev/null; then
      msg_error "Container creation failed after re-downloading template."
      exit 200
    fi
  else
    msg_error "Container creation failed, but template is not corrupted."
    exit 209
  fi
fi
msg_ok "LXC Container ${BL}$CTID${CL} ${GN}was successfully created."

}



variables() {
  NSAPP=$(echo "${APP,,}" | tr -d ' ')              # This function sets the NSAPP variable by converting the value of the APP variable to lowercase and removing any spaces.
  var_install="${NSAPP}-install"                    # sets the var_install variable by appending "-install" to the value of NSAPP.
  INTEGER='^[0-9]+([.][0-9]+)?$'                    # it defines the INTEGER regular expression pattern.
  PVEHOST_NAME=$(hostname)                          # gets the Proxmox Hostname and sets it to Uppercase
  METHOD="default"                                  # sets the METHOD variable to "default", used for the API call.
  RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)" # generates a random UUID and sets it to the RANDOM_UUID variable.
}



color() {
  YW=$(echo "\033[33m")
  YWB=$(echo "\033[93m")
  BL=$(echo "\033[36m")
  RD=$(echo "\033[01;31m")
  BGN=$(echo "\033[4;92m")
  GN=$(echo "\033[1;92m")
  DGN=$(echo "\033[32m")

  CL=$(echo "\033[m")
  BOLD=$(echo "\033[1m")
  HOLD=" "
  TAB="  "

  CM="${TAB}✔️${TAB}"
  CROSS="${TAB}✖️${TAB}"
  INFO="${TAB}💡${TAB}${CL}"
  OS="${TAB}🖥️${TAB}${CL}"
  OSVERSION="${TAB}🌟${TAB}${CL}"
  CONTAINERTYPE="${TAB}📦${TAB}${CL}"
  DISKSIZE="${TAB}💾${TAB}${CL}"
  CPUCORE="${TAB}🧠${TAB}${CL}"
  RAMSIZE="${TAB}🛠️${TAB}${CL}"
  SEARCH="${TAB}🔍${TAB}${CL}"
  VERBOSE_CROPPED="🔍${TAB}"
  VERIFYPW="${TAB}🔐${TAB}${CL}"
  CONTAINERID="${TAB}🆔${TAB}${CL}"
  HOSTNAME="${TAB}🏠${TAB}${CL}"
  BRIDGE="${TAB}🌉${TAB}${CL}"
  NETWORK="${TAB}📡${TAB}${CL}"
  GATEWAY="${TAB}🌐${TAB}${CL}"
  DISABLEIPV6="${TAB}🚫${TAB}${CL}"
  DEFAULT="${TAB}⚙️${TAB}${CL}"
  MACADDRESS="${TAB}🔗${TAB}${CL}"
  VLANTAG="${TAB}🏷️${TAB}${CL}"
  ROOTSSH="${TAB}🔑${TAB}${CL}"
  CREATING="${TAB}🚀${TAB}${CL}"
  ADVANCED="${TAB}🧩${TAB}${CL}"
}

catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

error_handler() {
  
  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then kill "$SPINNER_PID" >/dev/null; fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
}

declare -A MSG_INFO_SHOWN
SPINNER_ACTIVE=0
SPINNER_PID=""
SPINNER_MSG=""

trap 'stop_spinner' EXIT INT TERM HUP

start_spinner() {
  local msg="$1"
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local spin_i=0
  local interval=0.1

  SPINNER_MSG="$msg"
  printf "\r\e[2K" >&2

  {
    while [[ "$SPINNER_ACTIVE" -eq 1 ]]; do
      printf "\r\e[2K%s %b" "${frames[spin_i]}" "${YW}${SPINNER_MSG}${CL}" >&2
      spin_i=$(((spin_i + 1) % ${#frames[@]}))
      sleep "$interval"
    done
  } &

  SPINNER_PID=$!
  disown "$SPINNER_PID"
}

stop_spinner() {
  if [[ ${SPINNER_PID+v} && -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null
    sleep 0.1
    kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
  fi
  SPINNER_ACTIVE=0
  unset SPINNER_PID
}

spinner_guard() {
  if [[ "$SPINNER_ACTIVE" -eq 1 ]] && [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_ACTIVE=0
    unset SPINNER_PID
  fi
}

msg_info() {
  local msg="$1"
  [[ -n "${MSG_INFO_SHOWN["$msg"]+x}" ]] && return
  MSG_INFO_SHOWN["$msg"]=1

  spinner_guard
  SPINNER_ACTIVE=1
  start_spinner "$msg"
}

msg_ok() {
  local msg="$1"
  stop_spinner
  printf "\r\e[2K%s %b\n" "${CM}" "${GN}${msg}${CL}" >&2
  unset MSG_INFO_SHOWN["$msg"]
}

msg_error() {
  stop_spinner
  local msg="$1"
  printf "\r\e[2K%s %b\n" "${CROSS}" "${RD}${msg}${CL}" >&2
}

shell_check() {
  if [[ "$(basename "$SHELL")" != "bash" ]]; then
    clear
    msg_error "Your default shell is currently not set to Bash. To use these scripts, please switch to the Bash shell."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

root_check() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

pve_check() {
  if ! pveversion | grep -Eq "pve-manager/8\.[0-4](\.[0-9]+)*"; then
    msg_error "${CROSS}${RD}This version of Proxmox Virtual Environment is not supported"
    echo -e "Requires Proxmox Virtual Environment Version 8.1 or later."
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

maxkeys_check() {
  per_user_maxkeys=$(cat /proc/sys/kernel/keys/maxkeys 2>/dev/null || echo 0)
  per_user_maxbytes=$(cat /proc/sys/kernel/keys/maxbytes 2>/dev/null || echo 0)

  if [[ "$per_user_maxkeys" -eq 0 || "$per_user_maxbytes" -eq 0 ]]; then
    echo -e "${CROSS}${RD} Error: Unable to read kernel parameters. Ensure proper permissions.${CL}"
    exit 1
  fi

  used_lxc_keys=$(awk '/100000:/ {print $2}' /proc/key-users 2>/dev/null || echo 0)
  used_lxc_bytes=$(awk '/100000:/ {split($5, a, "/"); print a[1]}' /proc/key-users 2>/dev/null || echo 0)

  threshold_keys=$((per_user_maxkeys - 100))
  threshold_bytes=$((per_user_maxbytes - 1000))
  new_limit_keys=$((per_user_maxkeys * 2))
  new_limit_bytes=$((per_user_maxbytes * 2))

  failure=0
  if [[ "$used_lxc_keys" -gt "$threshold_keys" ]]; then
    echo -e "${CROSS}${RD} Warning: Key usage is near the limit (${used_lxc_keys}/${per_user_maxkeys}).${CL}"
    echo -e "${INFO} Suggested action: Set ${GN}kernel.keys.maxkeys=${new_limit_keys}${CL} in ${BOLD}/etc/sysctl.d/98-community-scripts.conf${CL}."
    failure=1
  fi
  if [[ "$used_lxc_bytes" -gt "$threshold_bytes" ]]; then
    echo -e "${CROSS}${RD} Warning: Key byte usage is near the limit (${used_lxc_bytes}/${per_user_maxbytes}).${CL}"
    echo -e "${INFO} Suggested action: Set ${GN}kernel.keys.maxbytes=${new_limit_bytes}${CL} in ${BOLD}/etc/sysctl.d/98-community-scripts.conf${CL}."
    failure=1
  fi

  if [[ "$failure" -eq 1 ]]; then
    echo -e "${INFO} To apply changes, run: ${BOLD}service procps force-reload${CL}"
    exit 1
  fi

  echo -e "${CM}${GN} All kernel key limits are within safe thresholds.${CL}"
}

arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}${YWB}This script will not work with PiMox! \n"
    echo -e "\n ${YWB}Visit https://github.com/asylumexp/Proxmox for ARM64 support. \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

get_current_ip() {
  if [ -f /etc/os-release ]; then
    if grep -qE 'ID=debian|ID=ubuntu' /etc/os-release; then
      CURRENT_IP=$(hostname -I | awk '{print $1}')
    elif grep -q 'ID=alpine' /etc/os-release; then
      CURRENT_IP=$(ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1)
    else
      CURRENT_IP="Unknown"
    fi
  fi
  echo "$CURRENT_IP"
}

update_motd_ip() {
  MOTD_FILE="/etc/motd"

  if [ -f "$MOTD_FILE" ]; then
    sed -i '/IP Address:/d' "$MOTD_FILE"

    IP=$(get_current_ip)
    echo -e "${TAB}${NETWORK}${YW} IP Address: ${GN}${IP}${CL}" >>"$MOTD_FILE"
  fi
}

get_header() {
  return 0
}

header_info() {
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

ssh_check() {
  if [ -n "${SSH_CLIENT:+x}" ]; then
    if whiptail --backtitle "SR7" --defaultno --title "SSH DETECTED" --yesno "It's advisable to utilize the Proxmox shell rather than SSH, as there may be potential complications with variable retrieval. Proceed using SSH?" 10 72; then
      whiptail --backtitle "SR7" --msgbox --title "Proceed using SSH" "You've chosen to proceed using SSH. If any issues arise, please run the script in the Proxmox shell before creating a repository issue." 10 72
    else
      clear
      echo "Exiting due to SSH usage. Please consider using the Proxmox shell."
      exit
    fi
  fi
}

base_settings() {
  CT_TYPE="1"
  DISK_SIZE="4"
  CORE_COUNT="1"
  RAM_SIZE="1024"
  VERBOSE="${1:-no}"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  SSH_AUTHORIZED_KEY=""
  TAGS="proxmox-script;"

  CT_TYPE=${var_unprivileged:-$CT_TYPE}
  DISK_SIZE=${var_disk:-$DISK_SIZE}
  CORE_COUNT=${var_cpu:-$CORE_COUNT}
  RAM_SIZE=${var_ram:-$RAM_SIZE}
  VERB=${var_verbose:-$VERBOSE}
  TAGS="${TAGS}${var_tags:-}"

  if [ -z "$var_os" ]; then
    var_os="debian"
  fi
  if [ -z "$var_version" ]; then
    var_version="12"
  fi
}

echo_default() {
  CT_TYPE_DESC="Unprivileged"
  if [ "$CT_TYPE" -eq 0 ]; then
    CT_TYPE_DESC="Privileged"
  fi

  echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}$var_os${CL}"
  echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Container Type: ${BGN}$CT_TYPE_DESC${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE} GB${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE} MiB${CL}"
  echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}${CT_ID}${CL}"
  if [ "$VERB" == "yes" ]; then
    echo -e "${SEARCH}${BOLD}${DGN}Verbose Mode: ${BGN}Enabled${CL}"
  fi
  echo -e "${CREATING}${BOLD}${BL}Creating a ${APP} LXC using the above default settings${CL}"
  echo -e "  "
}

exit_script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

advanced_settings() {
  whiptail --backtitle "SR7" --msgbox --title "Here is an instructional tip:" "To make a selection, use the Spacebar." 8 58
  TAGS="proxmox-script;${var_tags:-}"
  CT_DEFAULT_TYPE="${CT_TYPE}"
  CT_TYPE=""
  while [ -z "$CT_TYPE" ]; do
    if [ "$CT_DEFAULT_TYPE" == "1" ]; then
      if CT_TYPE=$(whiptail --backtitle "SR7" --title "CONTAINER TYPE" --radiolist "Choose Type" 10 58 2 \
        "1" "Unprivileged" ON \
        "0" "Privileged" OFF \
        3>&1 1>&2 2>&3); then
        if [ -n "$CT_TYPE" ]; then
          CT_TYPE_DESC="Unprivileged"
          if [ "$CT_TYPE" -eq 0 ]; then
            CT_TYPE_DESC="Privileged"
          fi
          echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}$var_os${CL}"
          echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
          echo -e "${CONTAINERTYPE}${BOLD}${DGN}Container Type: ${BGN}$CT_TYPE_DESC${CL}"
        fi
      else
        exit_script
      fi
    fi
    if [ "$CT_DEFAULT_TYPE" == "0" ]; then
      if CT_TYPE=$(whiptail --backtitle "SR7" --title "CONTAINER TYPE" --radiolist "Choose Type" 10 58 2 \
        "1" "Unprivileged" OFF \
        "0" "Privileged" ON \
        3>&1 1>&2 2>&3); then
        if [ -n "$CT_TYPE" ]; then
          CT_TYPE_DESC="Unprivileged"
          if [ "$CT_TYPE" -eq 0 ]; then
            CT_TYPE_DESC="Privileged"
          fi
          echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}$var_os${CL}"
          echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
          echo -e "${CONTAINERTYPE}${BOLD}${DGN}Container Type: ${BGN}$CT_TYPE_DESC${CL}"
        fi
      else
        exit_script
      fi
    fi
  done

  while true; do
    if PW1=$(whiptail --backtitle "SR7" --passwordbox "\nSet Root Password (needed for root ssh access)" 9 58 --title "PASSWORD (leave blank for automatic login)" 3>&1 1>&2 2>&3); then
      if [[ ! -z "$PW1" ]]; then
        if [[ "$PW1" == *" "* ]]; then
          whiptail --msgbox "Password cannot contain spaces. Please try again." 8 58
        elif [ ${#PW1} -lt 5 ]; then
          whiptail --msgbox "Password must be at least 5 characters long. Please try again." 8 58
        else
          if PW2=$(whiptail --backtitle "SR7" --passwordbox "\nVerify Root Password" 9 58 --title "PASSWORD VERIFICATION" 3>&1 1>&2 2>&3); then
            if [[ "$PW1" == "$PW2" ]]; then
              PW="-password $PW1"
              echo -e "${VERIFYPW}${BOLD}${DGN}Root Password: ${BGN}********${CL}"
              break
            else
              whiptail --msgbox "Passwords do not match. Please try again." 8 58
            fi
          else
            exit_script
          fi
        fi
      else
        PW1="Automatic Login"
        PW=""
        echo -e "${VERIFYPW}${BOLD}${DGN}Root Password: ${BGN}$PW1${CL}"
        break
      fi
    else
      exit_script
    fi
  done

  if CT_ID=$(whiptail --backtitle "SR7" --inputbox "Set Container ID" 8 58 "$NEXTID" --title "CONTAINER ID" 3>&1 1>&2 2>&3); then
    if [ -z "$CT_ID" ]; then
      CT_ID="$NEXTID"
      echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}$CT_ID${CL}"
    else
      echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}$CT_ID${CL}"
    fi
  else
    exit_script
  fi

  if CT_NAME=$(whiptail --backtitle "SR7" --inputbox "Set Hostname" 8 58 "$NSAPP" --title "HOSTNAME" 3>&1 1>&2 2>&3); then
    if [ -z "$CT_NAME" ]; then
      HN="$NSAPP"
    else
      HN=$(echo "${CT_NAME,,}" | tr -d ' ')
    fi
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
  else
    exit_script
  fi

  if DISK_SIZE=$(whiptail --backtitle "SR7" --inputbox "Set Disk Size in GB" 8 58 "$var_disk" --title "DISK SIZE" 3>&1 1>&2 2>&3); then
    if [ -z "$DISK_SIZE" ]; then
      DISK_SIZE="$var_disk"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE} GB${CL}"
    else
      if ! [[ $DISK_SIZE =~ $INTEGER ]]; then
        echo -e "{INFO}${HOLD}${RD} DISK SIZE MUST BE AN INTEGER NUMBER!${CL}"
        advanced_settings
      fi
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE} GB${CL}"
    fi
  else
    exit_script
  fi

  if CORE_COUNT=$(whiptail --backtitle "SR7" --inputbox "Allocate CPU Cores" 8 58 "$var_cpu" --title "CORE COUNT" 3>&1 1>&2 2>&3); then
    if [ -z "$CORE_COUNT" ]; then
      CORE_COUNT="$var_cpu"
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    else
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
    fi
  else
    exit_script
  fi

  if RAM_SIZE=$(whiptail --backtitle "SR7" --inputbox "Allocate RAM in MiB" 8 58 "$var_ram" --title "RAM" 3>&1 1>&2 2>&3); then
    if [ -z "$RAM_SIZE" ]; then
      RAM_SIZE="$var_ram"
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE} MiB${CL}"
    else
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE} MiB${CL}"
    fi
  else
    exit_script
  fi

  if BRG=$(whiptail --backtitle "SR7" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" 3>&1 1>&2 2>&3); then
    if [ -z "$BRG" ]; then
      BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit_script
  fi

  while true; do
    NET=$(whiptail --backtitle "SR7" --inputbox "Set a Static IPv4 CIDR Address (/24)" 8 58 dhcp --title "IP ADDRESS" 3>&1 1>&2 2>&3)
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
      if [ "$NET" = "dhcp" ]; then
        echo -e "${NETWORK}${BOLD}${DGN}IP Address: ${BGN}$NET${CL}"
        break
      else
        if [[ "$NET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
          echo -e "${NETWORK}${BOLD}${DGN}IP Address: ${BGN}$NET${CL}"
          break
        else
          whiptail --backtitle "SR7" --msgbox "$NET is an invalid IPv4 CIDR address. Please enter a valid IPv4 CIDR address or 'dhcp'" 8 58
        fi
      fi
    else
      exit_script
    fi
  done

  if [ "$NET" != "dhcp" ]; then
    while true; do
      GATE1=$(whiptail --backtitle "SR7" --inputbox "Enter gateway IP address" 8 58 --title "Gateway IP" 3>&1 1>&2 2>&3)
      if [ -z "$GATE1" ]; then
        whiptail --backtitle "SR7" --msgbox "Gateway IP address cannot be empty" 8 58
      elif [[ ! "$GATE1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        whiptail --backtitle "SR7" --msgbox "Invalid IP address format" 8 58
      else
        GATE=",gw=$GATE1"
        echo -e "${GATEWAY}${BOLD}${DGN}Gateway IP Address: ${BGN}$GATE1${CL}"
        break
      fi
    done
  else
    GATE=""
    echo -e "${GATEWAY}${BOLD}${DGN}Gateway IP Address: ${BGN}Default${CL}"
  fi

  if [ "$var_os" == "alpine" ]; then
    APT_CACHER=""
    APT_CACHER_IP=""
  else
    if APT_CACHER_IP=$(whiptail --backtitle "SR7" --inputbox "Set APT-Cacher IP (leave blank for none)" 8 58 --title "APT-Cacher IP" 3>&1 1>&2 2>&3); then
      APT_CACHER="${APT_CACHER_IP:+yes}"
      echo -e "${NETWORK}${BOLD}${DGN}APT-Cacher IP Address: ${BGN}${APT_CACHER_IP:-Default}${CL}"
    else
      exit_script
    fi
  fi

  if (whiptail --backtitle "SR7" --defaultno --title "IPv6" --yesno "Disable IPv6?" 10 58); then
    DISABLEIP6="yes"
  else
    DISABLEIP6="no"
  fi
  echo -e "${DISABLEIPV6}${BOLD}${DGN}Disable IPv6: ${BGN}$DISABLEIP6${CL}"

  if MTU1=$(whiptail --backtitle "SR7" --inputbox "Set Interface MTU Size (leave blank for default [The MTU of your selected vmbr, default is 1500])" 8 58 --title "MTU SIZE" 3>&1 1>&2 2>&3); then
    if [ -z "$MTU1" ]; then
      MTU1="Default"
      MTU=""
    else
      MTU=",mtu=$MTU1"
    fi
    echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
  else
    exit_script
  fi

  if SD=$(whiptail --backtitle "SR7" --inputbox "Set a DNS Search Domain (leave blank for HOST)" 8 58 --title "DNS Search Domain" 3>&1 1>&2 2>&3); then
    if [ -z "$SD" ]; then
      SX=Host
      SD=""
    else
      SX=$SD
      SD="-searchdomain=$SD"
    fi
    echo -e "${SEARCH}${BOLD}${DGN}DNS Search Domain: ${BGN}$SX${CL}"
  else
    exit_script
  fi

  if NX=$(whiptail --backtitle "SR7" --inputbox "Set a DNS Server IP (leave blank for HOST)" 8 58 --title "DNS SERVER IP" 3>&1 1>&2 2>&3); then
    if [ -z "$NX" ]; then
      NX=Host
      NS=""
    else
      NS="-nameserver=$NX"
    fi
    echo -e "${NETWORK}${BOLD}${DGN}DNS Server IP Address: ${BGN}$NX${CL}"
  else
    exit_script
  fi

  if MAC1=$(whiptail --backtitle "SR7" --inputbox "Set a MAC Address(leave blank for generated MAC)" 8 58 --title "MAC ADDRESS" 3>&1 1>&2 2>&3); then
    if [ -z "$MAC1" ]; then
      MAC1="Default"
      MAC=""
    else
      MAC=",hwaddr=$MAC1"
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC1${CL}"
    fi
  else
    exit_script
  fi

  if VLAN1=$(whiptail --backtitle "SR7" --inputbox "Set a Vlan(leave blank for no VLAN)" 8 58 --title "VLAN" 3>&1 1>&2 2>&3); then
    if [ -z "$VLAN1" ]; then
      VLAN1="Default"
      VLAN=""
    else
      VLAN=",tag=$VLAN1"
    fi
    echo -e "${VLANTAG}${BOLD}${DGN}Vlan: ${BGN}$VLAN1${CL}"
  else
    exit_script
  fi

  if ADV_TAGS=$(whiptail --backtitle "SR7" --inputbox "Set Custom Tags?[If you remove all, there will be no tags!]" 8 58 "${TAGS}" --title "Advanced Tags" 3>&1 1>&2 2>&3); then
    if [ -n "${ADV_TAGS}" ]; then
      ADV_TAGS=$(echo "$ADV_TAGS" | tr -d '[:space:]')
      TAGS="${ADV_TAGS}"
    else
      TAGS=";"
    fi
    echo -e "${NETWORK}${BOLD}${DGN}Tags: ${BGN}$TAGS${CL}"
  else
    exit_script
  fi

  if [[ "$PW" == -password* ]]; then
    if (whiptail --backtitle "SR7" --defaultno --title "SSH ACCESS" --yesno "Enable Root SSH Access?" 10 58); then
      SSH="yes"
    else
      SSH="no"
    fi
    echo -e "${ROOTSSH}${BOLD}${DGN}Root SSH Access: ${BGN}$SSH${CL}"
  else
    SSH="no"
    echo -e "${ROOTSSH}${BOLD}${DGN}Root SSH Access: ${BGN}$SSH${CL}"
  fi

  if [[ "${SSH}" == "yes" ]]; then
    SSH_AUTHORIZED_KEY="$(whiptail --backtitle "SR7" --inputbox "SSH Authorized key for root (leave empty for none)" 8 58 --title "SSH Key" 3>&1 1>&2 2>&3)"

    if [[ -z "${SSH_AUTHORIZED_KEY}" ]]; then
      echo "Warning: No SSH key provided."
    fi
  else
    SSH_AUTHORIZED_KEY=""
  fi
  if (whiptail --backtitle "SR7" --defaultno --title "VERBOSE MODE" --yesno "Enable Verbose Mode?" 10 58); then
    VERB="yes"
  else
    VERB="no"
  fi
  echo -e "${SEARCH}${BOLD}${DGN}Verbose Mode: ${BGN}$VERB${CL}"

  if (whiptail --backtitle "SR7" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create ${APP} LXC?" 10 58); then
    echo -e "${CREATING}${BOLD}${RD}Creating a ${APP} LXC using the above advanced settings${CL}"
  else
    clear
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings on node $PVEHOST_NAME${CL}"
    advanced_settings
  fi
}

diagnostics_check() {
  return 0
}

config_file() {

  whiptail --backtitle "SR7" --msgbox --title "Default distribution for $APP" "${var_os} ${var_version} \n \nIf the default Linux distribution is not adhered to, script support will be discontinued. \n" 10 58

  CONFIG_FILE="/opt/proxmox-scripts/.settings"

  if [[ -f "/opt/proxmox-scripts/${NSAPP}.conf" ]]; then
    CONFIG_FILE="/opt/proxmox-scripts/${NSAPP}.conf"
  fi

  if CONFIG_FILE=$(whiptail --backtitle "SR7" --inputbox "Set absolute path to config file" 8 58 "$CONFIG_FILE" --title "CONFIG FILE" 3>&1 1>&2 2>&3); then
    if [[ ! -f "$CONFIG_FILE" ]]; then
      echo -e "${CROSS}${RD}Config file not found, exiting script!.${CL}"
      exit
    else
      echo -e "${INFO}${BOLD}${DGN}Using config File: ${BGN}$CONFIG_FILE${CL}"
      base_settings
      source "$CONFIG_FILE"
    fi
  fi

  if [[ "$var_os" == "debian" ]]; then
    echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}$var_os${CL}"
    if [[ "$var_version" == "11" ]]; then
      echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
    elif [[ "$var_version" == "12" ]]; then
      echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
    else
      msg_error "Unknown setting for var_version, should be 11 or 12, was ${var_version}"
      exit
    fi
  elif [[ "$var_os" == "ubuntu" ]]; then
    echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}$var_os${CL}"
    if [[ "$var_version" == "20.04" ]]; then
      echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
    elif [[ "$var_version" == "22.04" ]]; then
      echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
    elif [[ "$var_version" == "24.04" ]]; then
      echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
    elif [[ "$var_version" == "24.10" ]]; then
      echo -e "${OSVERSION}${BOLD}${DGN}Version: ${BGN}$var_version${CL}"
    else
      msg_error "Unknown setting for var_version, should be 20.04, 22.04, 24.04 or 24.10, was ${var_version}"
      exit
    fi
  else
    msg_error "Unknown setting for var_os! should be debian or ubuntu, was ${var_os}"
    exit
  fi

  if [[ -n "$CT_ID" ]]; then

    if [[ "$CT_ID" =~ ^([0-9]{3,4})-([0-9]{3,4})$ ]]; then
      MIN_ID=${BASH_REMATCH[1]}
      MAX_ID=${BASH_REMATCH[2]}

      if ((MIN_ID >= MAX_ID)); then
        msg_error "Invalid Container ID range. The first number must be smaller than the second number, was ${CT_ID}"
        exit
      fi

      LIST_OF_IDS=$(pvesh get /cluster/resources --type vm --output-format json | grep -oP '"vmid":\s*\K\d+')

      for ((ID = MIN_ID; ID <= MAX_ID; ID++)); do
        if ! grep -q "^$ID$" <<<"$LIST_OF_IDS"; then
          CT_ID=$ID
          break
        fi
      done

      echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}$CT_ID${CL}"

    elif [[ "$CT_ID" =~ ^[0-9]+$ ]]; then

      LIST_OF_IDS=$(pvesh get /cluster/resources --type vm --output-format json | grep -oP '"vmid":\s*\K\d+')
      if ! grep -q "^$CT_ID$" <<<"$LIST_OF_IDS"; then
        echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}$CT_ID${CL}"
      else
        msg_error "Container ID $CT_ID already exists"
        exit
      fi
    else
      msg_error "Invalid Container ID format. Needs to be 0000-9999 or 0-9999, was ${CT_ID}"
      exit
    fi
  fi

  if [[ "$CT_TYPE" -eq 0 ]]; then
    CT_TYPE_DESC="Privileged"
  elif [[ "$CT_TYPE" -eq 1 ]]; then
    CT_TYPE_DESC="Unprivileged"
  else
    msg_error "Unknown setting for CT_TYPE, should be 1 or 0, was ${CT_TYPE}"
    exit
  fi
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Container Type: ${BGN}$CT_TYPE_DESC${CL}"

  if [[ ! -z "$PW" ]]; then

    if [[ "$PW" == *" "* ]]; then
      msg_error "Password cannot be empty"
      exit
    elif [[ ${#PW} -lt 5 ]]; then
      msg_error "Password must be at least 5 characters long"
      exit
    else
      echo -e "${VERIFYPW}${BOLD}${DGN}Root Password: ${BGN}********${CL}"
    fi
    PW="-password $PW"
  else
    PW=""
    echo -e "${VERIFYPW}${BOLD}${DGN}Root Password: ${BGN}Automatic Login${CL}"
  fi
  echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}$CT_ID${CL}"

  if [[ ! -z "$HN" ]]; then
    echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
  else
    msg_error "Hostname cannot be empty"
    exit
  fi

  if [[ ! -z "$DISK_SIZE" ]]; then
    if [[ "$DISK_SIZE" =~ ^-?[0-9]+$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE} GB${CL}"
    else
      msg_error "DISK_SIZE must be an integer, was ${DISK_SIZE}"
      exit
    fi
  else
    msg_error "DISK_SIZE cannot be empty"
    exit
  fi

  if [[ ! -z "$CORE_COUNT" ]]; then
    if [[ "$CORE_COUNT" =~ ^-?[0-9]+$ ]]; then
      echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
    else
      msg_error "CORE_COUNT must be an integer, was ${CORE_COUNT}"
      exit
    fi
  else
    msg_error "CORE_COUNT cannot be empty"
    exit
  fi

  if [[ ! -z "$RAM_SIZE" ]]; then
    if [[ "$RAM_SIZE" =~ ^-?[0-9]+$ ]]; then
      echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE} MiB${CL}"
    else
      msg_error "RAM_SIZE must be an integer, was ${RAM_SIZE}"
      exit
    fi
  else
    msg_error "RAM_SIZE cannot be empty"
    exit
  fi

  if [[ ! -z "$BRG" ]]; then
    if grep -q "^iface ${BRG}" /etc/network/interfaces; then
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      msg_error "Bridge '${BRG}' does not exist in /etc/network/interfaces"
      exit
    fi
  else
    msg_error "Bridge cannot be empty"
    exit
  fi

  local ip_cidr_regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$'
  local ip_regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'

  if [[ ! -z $NET ]]; then
    if [ "$NET" == "dhcp" ]; then
      echo -e "${NETWORK}${BOLD}${DGN}IP Address: ${BGN}DHCP${CL}"
      echo -e "${GATEWAY}${BOLD}${DGN}Gateway IP Address: ${BGN}Default${CL}"
    elif
      [[ "$NET" =~ $ip_cidr_regex ]]
    then
      echo -e "${NETWORK}${BOLD}${DGN}IP Address: ${BGN}$NET${CL}"
    else
      msg_error "Invalid IP Address format. Needs to be 0.0.0.0/0, was ${NET}"
      exit
    fi
  fi
  if [ ! -z "$GATE" ]; then
    if [[ "$GATE" =~ $ip_regex ]]; then
      echo -e "${GATEWAY}${BOLD}${DGN}Gateway IP Address: ${BGN}$GATE${CL}"
      GATE=",gw=$GATE"
    else
      msg_error "Invalid IP Address format for Gateway. Needs to be 0.0.0.0, was ${GATE}"
      exit
    fi
  else
    msg_error "Gateway IP Address cannot be empty"
    exit
  fi

  if [[ ! -z "$APT_CACHER_IP" ]]; then
    if [[ "$APT_CACHER_IP" =~ $ip_regex ]]; then
      APT_CACHER="yes"
      echo -e "${NETWORK}${BOLD}${DGN}APT-CACHER IP Address: ${BGN}$APT_CACHER_IP${CL}"
    else
      msg_error "Invalid IP Address format for APT-Cacher. Needs to be 0.0.0.0, was ${APT_CACHER_IP}"
      exit
    fi
  fi

  if [[ "$DISABLEIP6" == "yes" ]]; then
    echo -e "${DISABLEIPV6}${BOLD}${DGN}Disable IPv6: ${BGN}Yes${CL}"
  elif [[ "$DISABLEIP6" == "no" ]]; then
    echo -e "${DISABLEIPV6}${BOLD}${DGN}Disable IPv6: ${BGN}No${CL}"
  else
    msg_error "Disable IPv6 needs to be 'yes' or 'no'"
    exit
  fi

  if [[ ! -z "$MTU" ]]; then
    if [[ "$MTU" =~ ^-?[0-9]+$ ]]; then
      echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU${CL}"
      MTU=",mtu=$MTU"
    else
      msg_error "MTU must be an integer, was ${MTU}"
      exit
    fi
  else
    MTU=""
    echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"

  fi

  if [[ ! -z "$SD" ]]; then
    echo -e "${SEARCH}${BOLD}${DGN}DNS Search Domain: ${BGN}$SD${CL}"
    SD="-searchdomain=$SD"
  else
    SD=""
    echo -e "${SEARCH}${BOLD}${DGN}DNS Search Domain: ${BGN}HOST${CL}"
  fi

  if [[ ! -z "$NS" ]]; then
    if [[ "$NS" =~ $ip_regex ]]; then
      echo -e "${NETWORK}${BOLD}${DGN}DNS Server IP Address: ${BGN}$NS${CL}"
      NS="-nameserver=$NS"
    else
      msg_error "Invalid IP Address format for DNS Server. Needs to be 0.0.0.0, was ${NS}"
      exit
    fi
  else
    NS=""
    echo -e "${NETWORK}${BOLD}${DGN}DNS Server IP Address: ${BGN}HOST${CL}"
  fi

  if [[ ! -z "$MAC" ]]; then
    if [[ "$MAC" =~ ^([A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}$ ]]; then
      echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
      MAC=",hwaddr=$MAC"
    else
      msg_error "MAC Address must be in the format xx:xx:xx:xx:xx:xx, was ${MAC}"
      exit
    fi
  fi

  if [[ ! -z "$VLAN" ]]; then
    if [[ "$VLAN" =~ ^-?[0-9]+$ ]]; then
      echo -e "${VLANTAG}${BOLD}${DGN}Vlan: ${BGN}$VLAN${CL}"
      VLAN=",tag=$VLAN"
    else
      msg_error "VLAN must be an integer, was ${VLAN}"
      exit
    fi
  fi

  if [[ ! -z "$TAGS" ]]; then
    echo -e "${NETWORK}${BOLD}${DGN}Tags: ${BGN}$TAGS${CL}"
  fi

  if [[ "$SSH" == "yes" ]]; then
    echo -e "${ROOTSSH}${BOLD}${DGN}Root SSH Access: ${BGN}$SSH${CL}"
    if [[ ! -z "$SSH_AUTHORIZED_KEY" ]]; then
      echo -e "${ROOTSSH}${BOLD}${DGN}SSH Authorized Key: ${BGN}********************${CL}"
    else
      echo -e "${ROOTSSH}${BOLD}${DGN}SSH Authorized Key: ${BGN}None${CL}"
    fi
  elif [[ "$SSH" == "no" ]]; then
    echo -e "${ROOTSSH}${BOLD}${DGN}Root SSH Access: ${BGN}$SSH${CL}"
  else
    msg_error "SSH needs to be 'yes' or 'no', was ${SSH}"
    exit
  fi

  if [[ "$VERB" == "yes" ]]; then
    echo -e "${SEARCH}${BOLD}${DGN}Verbose Mode: ${BGN}$VERB${CL}"
  elif [[ "$VERB" == "no" ]]; then
    echo -e "${SEARCH}${BOLD}${DGN}Verbose Mode: ${BGN}No${CL}"
  else
    msg_error "Verbose Mode needs to be 'yes' or 'no', was ${VERB}"
    exit
  fi

  if (whiptail --backtitle "SR7" --title "ADVANCED SETTINGS WITH CONFIG FILE COMPLETE" --yesno "Ready to create ${APP} LXC?" 10 58); then
    echo -e "${CREATING}${BOLD}${RD}Creating a ${APP} LXC using the above settings${CL}"
  else
    clear
    header_info
    echo -e "${INFO}${HOLD} ${GN}Using Config File on node $PVEHOST_NAME${CL}"
    config_file
  fi

}

install_script() {
  pve_check
  shell_check
  root_check
  arch_check
  ssh_check
  maxkeys_check
  diagnostics_check

  if systemctl is-active -q ping-instances.service; then
    systemctl -q stop ping-instances.service
  fi
  NEXTID=$(pvesh get /cluster/nextid)
  timezone=$(cat /etc/timezone)
  header_info
  while true; do

    CHOICE=$(whiptail --backtitle "SR7" --title "SETTINGS" --menu "Choose an option:" \
      18 60 6 \
      "1" "Default Settings" \
      "2" "Default Settings (with verbose)" \
      "3" "Advanced Settings" \
      "4" "Use Config File" \
      "5" "Exit" --nocancel --default-item "1" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
      echo -e "${CROSS}${RD} Menu canceled. Exiting.${CL}"
      exit 0
    fi

    case $CHOICE in
    1)
      header_info
      echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings on node $PVEHOST_NAME${CL}"
      VERB="no"
      METHOD="default"
      base_settings "$VERB"
      echo_default
      break
      ;;
    2)
      header_info
      echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings on node $PVEHOST_NAME (${VERBOSE_CROPPED}Verbose)${CL}"
      VERB="yes"
      METHOD="default"
      base_settings "$VERB"
      echo_default
      break
      ;;
    3)
      header_info
      echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings on node $PVEHOST_NAME${CL}"
      METHOD="advanced"
      base_settings
      advanced_settings
      break
      ;;
    4)
      header_info
      echo -e "${INFO}${HOLD} ${GN}Using Config File on node $PVEHOST_NAME${CL}"
      METHOD="advanced"
      base_settings
      config_file
      break
      ;;
    5)
      echo -e "${CROSS}${RD}Exiting.${CL}"
      exit 0
      ;;
    *)
      echo -e "${CROSS}${RD}Invalid option, please try again.${CL}"
      ;;
    esac
  done
}

check_container_resources() {
  current_ram=$(free -m | awk 'NR==2{print $2}')
  current_cpu=$(nproc)

  if [[ "$current_ram" -lt "$var_ram" ]] || [[ "$current_cpu" -lt "$var_cpu" ]]; then
    echo -e "\n${INFO}${HOLD} ${GN}Required: ${var_cpu} CPU, ${var_ram}MB RAM ${CL}| ${RD}Current: ${current_cpu} CPU, ${current_ram}MB RAM${CL}"
    echo -e "${YWB}Please ensure that the ${APP} LXC is configured with at least ${var_cpu} vCPU and ${var_ram} MB RAM for the build process.${CL}\n"
    echo -ne "${INFO}${HOLD} May cause data loss! ${INFO} Continue update with under-provisioned LXC? <yes/No>  "
    read -r prompt
    if [[ ! ${prompt,,} =~ ^(yes)$ ]]; then
      echo -e "${CROSS}${HOLD} ${YWB}Exiting based on user input.${CL}"
      exit 1
    fi
  else
    echo -e ""
  fi
}

check_container_storage() {
  total_size=$(df /boot --output=size | tail -n 1)
  local used_size=$(df /boot --output=used | tail -n 1)
  usage=$((100 * used_size / total_size))
  if ((usage > 80)); then
    echo -e "${INFO}${HOLD} ${YWB}Warning: Storage is dangerously low (${usage}%).${CL}"
    echo -ne "Continue anyway? <y/N>  "
    read -r prompt
    if [[ ! ${prompt,,} =~ ^(y|yes)$ ]]; then
      echo -e "${CROSS}${HOLD}${YWB}Exiting based on user input.${CL}"
      exit 1
    fi
  fi
}

start() {
    if [[ -n "$TOOLS_FUNC_CONTENT" ]]; then
    source <(echo "$TOOLS_FUNC_CONTENT")
  else
    source $(dirname ${BASH_SOURCE[0]})/tools.func
  fi
  if command -v pveversion >/dev/null 2>&1; then
    if ! (whiptail --backtitle "SR7" --title "${APP} LXC" --yesno "This will create a New ${APP} LXC. Proceed?" 10 58); then
      clear
      exit_script
      exit
    fi
    SPINNER_PID=""
    install_script
  fi

  if ! command -v pveversion >/dev/null 2>&1; then
    CHOICE=$(whiptail --backtitle "SR7" --title "${APP} LXC Update/Setting" --menu \
      "Support/Update functions for ${APP} LXC. Choose an option:" \
      12 60 3 \
      "1" "YES (Silent Mode)" \
      "2" "YES (Verbose Mode)" \
      "3" "NO (Cancel Update)" --nocancel --default-item "1" 3>&1 1>&2 2>&3)

    case "$CHOICE" in
    1)
      VERB="no"
      set_std_mode
      ;;
    2)
      VERB="yes"
      set_std_mode
      ;;
    3)
      clear
      exit_script
      exit
      ;;
    esac

    SPINNER_PID=""
    update_script
  fi
}

build_container() {

  if [ "$CT_TYPE" == "1" ]; then
    FEATURES="keyctl=1,nesting=1"
  else
    FEATURES="nesting=1"
  fi



  TEMP_DIR=$(mktemp -d)
  pushd "$TEMP_DIR" >/dev/null
  if [ "$var_os" == "alpine" ]; then
    export FUNCTIONS_FILE_PATH="$ALPINE_INSTALL_FUNC_CONTENT"
  else
    export FUNCTIONS_FILE_PATH="$API_FUNC_CONTENT
$TOOLS_FUNC_CONTENT
$INSTALL_FUNC_CONTENT"
  fi
  export RANDOM_UUID="$RANDOM_UUID"
  export CACHER="$APT_CACHER"
  export CACHER_IP="$APT_CACHER_IP"
  export tz="$timezone"
  export DISABLEIPV6="$DISABLEIP6"
  export APPLICATION="$APP"
  export app="$NSAPP"
  export PASSWORD="$PW"
  export VERBOSE="$VERB"
  export SSH_ROOT="${SSH}"
  export SSH_AUTHORIZED_KEY
  export CTID="$CT_ID"
  export CTTYPE="$CT_TYPE"
  export PCT_OSTYPE="$var_os"
  export PCT_OSVERSION="$var_version"
  export PCT_DISK_SIZE="$DISK_SIZE"
  export PCT_OPTIONS="
    -features $FEATURES
    -hostname $HN
    -tags $TAGS
    $SD
    $NS
    -net0 name=eth0,bridge=$BRG$MAC,ip=$NET$GATE$VLAN$MTU
    -onboot 1
    -cores $CORE_COUNT
    -memory $RAM_SIZE
    -unprivileged $CT_TYPE
    $PW
  "
  create_lxc $?

  LXC_CONFIG=/etc/pve/lxc/${CTID}.conf
  if [ "$CT_TYPE" == "0" ]; then
    cat <<EOF >>"$LXC_CONFIG"
# USB passthrough
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
lxc.cgroup2.devices.allow: c 188:* rwm
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/serial/by-id  dev/serial/by-id  none bind,optional,create=dir
lxc.mount.entry: /dev/ttyUSB0       dev/ttyUSB0       none bind,optional,create=file
lxc.mount.entry: /dev/ttyUSB1       dev/ttyUSB1       none bind,optional,create=file
lxc.mount.entry: /dev/ttyACM0       dev/ttyACM0       none bind,optional,create=file
lxc.mount.entry: /dev/ttyACM1       dev/ttyACM1       none bind,optional,create=file
EOF
  fi

  if [ "$CT_TYPE" == "0" ]; then
    if [[ "$APP" == "Channels" || "$APP" == "Emby" || "$APP" == "ErsatzTV" || "$APP" == "Frigate" || "$APP" == "Jellyfin" || "$APP" == "Plex" || "$APP" == "Scrypted" || "$APP" == "Tdarr" || "$APP" == "Unmanic" || "$APP" == "Ollama" || "$APP" == "FileFlows" ]]; then
      cat <<EOF >>"$LXC_CONFIG"
# VAAPI hardware transcoding
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
EOF
    fi
  else
    if [[ "$APP" == "Channels" || "$APP" == "Emby" || "$APP" == "ErsatzTV" || "$APP" == "Frigate" || "$APP" == "Jellyfin" || "$APP" == "Plex" || "$APP" == "Scrypted" || "$APP" == "Tdarr" || "$APP" == "Unmanic" || "$APP" == "Ollama" || "$APP" == "FileFlows" ]]; then
      if [[ -e "/dev/dri/renderD128" ]]; then
        if [[ -e "/dev/dri/card0" ]]; then
          cat <<EOF >>"$LXC_CONFIG"
# VAAPI hardware transcoding
dev0: /dev/dri/card0,gid=44
dev1: /dev/dri/renderD128,gid=104
EOF
        else
          cat <<EOF >>"$LXC_CONFIG"
# VAAPI hardware transcoding
dev0: /dev/dri/card1,gid=44
dev1: /dev/dri/renderD128,gid=104
EOF
        fi
      fi
    fi
  fi

  msg_info "Starting LXC Container"
  pct start "$CTID"
  msg_ok "Started LXC Container"
  if [ "$var_os" == "alpine" ]; then
    sleep 3
    pct exec "$CTID" -- /bin/sh -c 'cat <<EOF >/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/latest-stable/main
http://dl-cdn.alpinelinux.org/alpine/latest-stable/community
EOF'
    pct exec "$CTID" -- ash -c "apk add bash >/dev/null"
  fi
  lxc-attach -n "$CTID" -- bash -c "$INSTALL_SCRIPT_CONTENT" $?

}

# This function sets the description of the container.
description() {
  IP=$(pct exec "$CTID" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

  # Generate LXC Description
  DESCRIPTION="${APP} LXC"

  # Set Description in LXC
  pct set "$CTID" -description "$DESCRIPTION"

  if [[ -f /etc/systemd/system/ping-instances.service ]]; then
    systemctl start ping-instances.service
  fi


}

set_std_mode() {
  if [ "$VERB" = "yes" ]; then
    STD=""
  else
    STD="silent"
  fi
}

# Silent execution function
silent() {
  if [ "$VERB" = "no" ]; then
    "$@" >/dev/null 2>&1 || return 1
  else
    "$@" || return 1
  fi
}

api_exit_script() {
  exit_code=$? # Capture the exit status of the last executed command
  #200 exit codes indicate error in create_lxc.sh
  #100 exit codes indicate error in install.func

  if [ $exit_code -ne 0 ]; then
    case $exit_code in
    100) post_update_to_api "failed" "100: Unexpected error in create_lxc.sh" ;;
    101) post_update_to_api "failed" "101: No network connection detected in create_lxc.sh" ;;
    200) post_update_to_api "failed" "200: LXC creation failed in create_lxc.sh" ;;
    201) post_update_to_api "failed" "201: Invalid Storage class in create_lxc.sh" ;;
    202) post_update_to_api "failed" "202: User aborted menu in create_lxc.sh" ;;
    203) post_update_to_api "failed" "203: CTID not set in create_lxc.sh" ;;
    204) post_update_to_api "failed" "204: PCT_OSTYPE not set in create_lxc.sh" ;;
    205) post_update_to_api "failed" "205: CTID cannot be less than 100 in create_lxc.sh" ;;
    206) post_update_to_api "failed" "206: CTID already in use in create_lxc.sh" ;;
    207) post_update_to_api "failed" "207: Template not found in create_lxc.sh" ;;
    208) post_update_to_api "failed" "208: Error downloading template in create_lxc.sh" ;;
    209) post_update_to_api "failed" "209: Container creation failed, but template is intact in create_lxc.sh" ;;
    *) post_update_to_api "failed" "Unknown error, exit code: $exit_code in create_lxc.sh" ;;
    esac
  fi
}

trap 'api_exit_script' EXIT
trap 'post_update_to_api "failed" "$BASH_COMMAND"' ERR
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM






APP="Headscale"
var_tags="${var_tags:-tailscale}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/headscale ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/juanfont/headscale/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Stopping ${APP}"
    systemctl stop headscale
    msg_ok "Stopped ${APP}"

    msg_info "Updating $APP to v${RELEASE}"
    curl -fsSL "https://github.com/juanfont/headscale/releases/download/v${RELEASE}/headscale_${RELEASE}_linux_amd64.deb" -o $(basename "https://github.com/juanfont/headscale/releases/download/v${RELEASE}/headscale_${RELEASE}_linux_amd64.deb")
    dpkg -i headscale_${RELEASE}_linux_amd64.deb
    rm headscale_${RELEASE}_linux_amd64.deb
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated $APP to ${RELEASE}"

    msg_info "Starting ${APP}"
    # Temporary fix until headscale project resolves service getting disabled on updates.
    systemctl enable -q --now headscale
    msg_ok "Started ${APP}"
    msg_ok "Updated Successfully"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
