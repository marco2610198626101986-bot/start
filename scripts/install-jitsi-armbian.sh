#!/usr/bin/env bash
#
# Install Jitsi Meet on Armbian (Debian/Ubuntu-based ARM boards).
# Tested on aarch64 (arm64). armhf may require additional manual steps.
#
# Usage:
#   sudo ./install-jitsi-armbian.sh --domain meet.example.org
#   sudo ./install-jitsi-armbian.sh --domain meet.example.org --disable-zram --nat
#
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

DOMAIN=""
DISABLE_ZRAM=false
CONFIGURE_NAT=false
SKIP_SCTP_BUILD=false
PUBLIC_IP=""
LOCAL_IP=""

usage() {
  cat <<EOF
Usage: sudo $SCRIPT_NAME --domain FQDN [options]

Required:
  --domain FQDN          Hostname for Jitsi Meet (e.g. meet.example.org)

Options:
  --disable-zram         Disable Armbian zram swap (recommended on boards with <= 4 GB RAM)
  --nat                  Configure static ICE mapping in jvb.conf (for servers behind NAT)
  --public-ip IP         Public IP for NAT mapping (auto-detected if omitted with --nat)
  --local-ip IP          Local IP for NAT mapping (auto-detected if omitted with --nat)
  --skip-sctp-build      Skip ARM64 libjnisctp rebuild (use if video already works)
  -h, --help             Show this help

Before running:
  1. Point DNS A record for the domain to your public IP.
  2. Forward ports 80/tcp, 443/tcp, 10000/udp to this host on your router.
  3. Use Armbian based on Debian 11+ or Ubuntu 22.04+ (Bookworm/Jammy or newer).
EOF
}

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root: sudo $SCRIPT_NAME ..."
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)
        DOMAIN="${2:-}"
        shift 2
        ;;
      --disable-zram)
        DISABLE_ZRAM=true
        shift
        ;;
      --nat)
        CONFIGURE_NAT=true
        shift
        ;;
      --public-ip)
        PUBLIC_IP="${2:-}"
        shift 2
        ;;
      --local-ip)
        LOCAL_IP="${2:-}"
        shift 2
        ;;
      --skip-sctp-build)
        SKIP_SCTP_BUILD=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1 (use --help)"
        ;;
    esac
  done

  [[ -n "$DOMAIN" ]] || die "Missing required option: --domain"
}

detect_arch() {
  ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  log "Architecture: $ARCH"
}

check_os() {
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS (/etc/os-release missing)"
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  log "OS: ${PRETTY_NAME:-unknown}"

  case "${ID:-}:${VERSION_ID:-}" in
    debian:11|debian:12|ubuntu:22.04|ubuntu:24.04)
      ;;
    armbian:*)
      log "Armbian detected (based on ${VERSION_CODENAME:-unknown})"
      ;;
    *)
      log "WARNING: Untested OS. Jitsi officially supports Debian 11+ and Ubuntu 22.04+."
      read -r -p "Continue anyway? [y/N] " reply
      [[ "${reply,,}" == "y" ]] || exit 1
      ;;
  esac
}

check_resources() {
  local mem_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  local mem_mb=$((mem_kb / 1024))
  log "RAM: ${mem_mb} MB"

  if (( mem_mb < 2048 )); then
    log "WARNING: Less than 2 GB RAM. Jitsi may be unstable for multi-party calls."
  fi
}

disable_zram_if_requested() {
  if [[ "$DISABLE_ZRAM" != true ]]; then
    return
  fi

  log "Disabling Armbian zram services..."
  swapoff -a 2>/dev/null || true
  systemctl disable armbian-zram-config.service 2>/dev/null || true
  systemctl disable armbian-ramlog.service 2>/dev/null || true
  systemctl stop armbian-zram-config.service 2>/dev/null || true
  systemctl stop armbian-ramlog.service 2>/dev/null || true
}

configure_hostname() {
  log "Setting hostname to $DOMAIN"
  hostnamectl set-hostname "$DOMAIN"

  if ! grep -q "$DOMAIN" /etc/hosts; then
    LOCAL_IP="${LOCAL_IP:-$(hostname -I | awk '{print $1}')}"
    echo "${LOCAL_IP} ${DOMAIN}" >> /etc/hosts
  fi
}

install_prerequisites() {
  log "Installing prerequisites..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    lua5.2 \
    nginx-full \
    openjdk-17-jre-headless

  if [[ "${ID:-}" == "ubuntu" ]]; then
    add-apt-repository -y universe 2>/dev/null || true
    apt-get update
  fi
}

add_prosody_repo() {
  log "Adding Prosody repository..."
  curl -sL https://prosody.im/files/prosody-debian-packages.key \
    -o /usr/share/keyrings/prosody-debian-packages.key
  echo "deb [signed-by=/usr/share/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main" \
    > /etc/apt/sources.list.d/prosody-debian-packages.list
}

add_jitsi_repo() {
  log "Adding Jitsi repository..."
  curl -sL https://download.jitsi.org/jitsi-key.gpg.key \
    | gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/" \
    > /etc/apt/sources.list.d/jitsi-stable.list
  apt-get update
}

configure_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    log "ufw not installed, skipping firewall configuration"
    return
  fi

  log "Configuring ufw..."
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 10000/udp
  ufw allow 22/tcp
  ufw allow 3478/udp
  ufw allow 5349/tcp
  ufw --force enable
  ufw status verbose || true
}

preseed_jitsi_install() {
  log "Preseeding debconf for non-interactive install..."
  echo "jitsi-meet jitsi-meet/jvb-hostname string ${DOMAIN}" \
    | debconf-set-selections
  echo "jitsi-meet jitsi-meet/cert-choice select Let's encrypt certificates" \
    | debconf-set-selections
  echo "jitsi-meet jitsi-meet/email string admin@${DOMAIN#*.}" \
    | debconf-set-selections
}

install_jitsi() {
  log "Installing jitsi-meet (this may take several minutes on ARM)..."
  apt-get install -y jitsi-meet
}

build_arm64_sctp_if_needed() {
  if [[ "$SKIP_SCTP_BUILD" == true ]]; then
    log "Skipping SCTP native library build (--skip-sctp-build)"
    return
  fi

  if [[ "$ARCH" != "arm64" && "$ARCH" != "aarch64" ]]; then
    log "Non-arm64 architecture; skipping SCTP rebuild"
    return
  fi

  local jvb_lib="/usr/share/jitsi-videobridge/lib"
  local jni_jar
  jni_jar="$(ls "${jvb_lib}"/jniwrapper-native-*.jar 2>/dev/null | head -n1 || true)"

  if [[ -z "$jni_jar" ]]; then
    log "jniwrapper jar not found; skipping SCTP rebuild"
    return
  fi

  if unzip -l "$jni_jar" 2>/dev/null | grep -q 'lib/linux-aarch64/libjnisctp.so'; then
    log "ARM64 libjnisctp already present in $jni_jar"
    return
  fi

  log "Building libjnisctp for ARM64..."
  systemctl stop jicofo jitsi-videobridge2 prosody 2>/dev/null || true

  apt-get install -y automake autoconf build-essential git libtool maven m4

  local build_dir
  build_dir="$(mktemp -d /tmp/jitsi-sctp-build.XXXXXX)"
  trap 'rm -rf "$build_dir"' RETURN

  git clone --depth 1 https://github.com/sctplab/usrsctp.git "${build_dir}/usrsctp"
  git clone --depth 1 https://github.com/jitsi/jitsi-sctp "${build_dir}/jitsi-sctp"
  mv "${build_dir}/usrsctp" "${build_dir}/jitsi-sctp/usrsctp/"

  cd "${build_dir}/jitsi-sctp"
  export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"

  mvn -q package -DbuildSctp -DbuildNativeWrapper -DdeployNewJnilib -DskipTests
  cp ./jniwrapper/native/target/libjnisctp-linux-aarch64.so \
    ./jniwrapper/native/src/main/resources/lib/linux-aarch64/libjnisctp.so 2>/dev/null \
    || cp ./jniwrapper/native/target/libjnisctp-linux-* \
      ./jniwrapper/native/src/main/resources/lib/linux/libjnisctp.so
  mvn -q package

  cp ./jniwrapper/native/target/jniwrapper-native-1.0-SNAPSHOT.jar "$jni_jar"
  log "Updated $jni_jar with ARM64 native library"

  systemctl start prosody jitsi-videobridge2 jicofo
}

configure_nat() {
  if [[ "$CONFIGURE_NAT" != true ]]; then
    return
  fi

  LOCAL_IP="${LOCAL_IP:-$(hostname -I | awk '{print $1}')}"
  if [[ -z "$PUBLIC_IP" ]]; then
    PUBLIC_IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org || curl -4 -fsS --max-time 10 https://ifconfig.me/ip)"
  fi

  log "Configuring NAT: local=${LOCAL_IP} public=${PUBLIC_IP}"

  local jvb_conf="/etc/jitsi/videobridge/jvb.conf"
  if grep -q 'static-mappings' "$jvb_conf" 2>/dev/null; then
    log "static-mappings already present in $jvb_conf"
    return
  fi

  cat >> "$jvb_conf" <<EOF

# Added by ${SCRIPT_NAME} for NAT traversal
ice4j {
  harvest {
    mapping {
      static-mappings = [
        {
          local-address = "${LOCAL_IP}"
          public-address = "${PUBLIC_IP}"
        }
      ]
    }
  }
}
EOF

  systemctl restart jitsi-videobridge2
}

install_letsencrypt_if_needed() {
  if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    log "Let's Encrypt certificate already present"
    return
  fi

  if [[ -x /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh ]]; then
    log "Running Jitsi Let's Encrypt installer..."
    /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh || \
      log "WARNING: Let's Encrypt install failed. Run manually later."
  fi
}

print_summary() {
  cat <<EOF

================================================================================
Jitsi Meet installation finished.

  URL:      https://${DOMAIN}
  Logs:     /var/log/jitsi/jvb.log
            /var/log/jitsi/jicofo.log
            /var/log/prosody/prosody.log

Services:
  systemctl status prosody jitsi-videobridge2 jicofo nginx

If video fails with 3+ participants on ARM64, rebuild SCTP without --skip-sctp-build
or check /var/log/jitsi/jvb.log for UnsatisfiedLinkError / libjnisctp errors.

================================================================================
EOF
}

main() {
  parse_args "$@"
  require_root
  detect_arch
  check_os
  check_resources
  disable_zram_if_requested
  configure_hostname
  install_prerequisites
  add_prosody_repo
  add_jitsi_repo
  configure_firewall
  preseed_jitsi_install
  install_jitsi
  build_arm64_sctp_if_needed
  configure_nat
  install_letsencrypt_if_needed
  print_summary
}

main "$@"
