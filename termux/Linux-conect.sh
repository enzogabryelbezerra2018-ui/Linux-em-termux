#!/data/data/com.termux/files/usr/bin/env bash
# linux-termux-pc-connect
# Uso seguro: conectar via SSH ao SEU PC após conectar cabo USB e ativar USB tethering.
# Não usar para acessar máquinas sem autorização.

set -e
SCRIPT_NAME="$(basename "$0")"

ensure_pkg() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[+] Instalando $1..."
    pkg install -y "$1"
  fi
}

print_help() {
  cat <<-EOF
Uso: $SCRIPT_NAME [--ip IP|--auto] [--user USER] [--port PORT] [--key ~/.ssh/id_rsa]
Exemplos:
  $SCRIPT_NAME --auto
  $SCRIPT_NAME --ip 192.168.42.1 --user meu_usuario
  $SCRIPT_NAME --auto --user meu_usuario --key ~/.ssh/id_rsa
Observações:
  - Antes de rodar, conecte o cabo USB e ative "USB tethering" (ou configure adb forwarding).
  - O script tenta conectar via SSH ao seu PC. Você precisa ter servidor SSH no PC.
EOF
}

# defaults
PORT=22
USE_KEY=""
USER=""
IP_ARG=""
AUTO_DETECT=0

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0;;
    --auto) AUTO_DETECT=1; shift;;
    --ip) IP_ARG="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --key) USE_KEY="$2"; shift 2;;
    *) echo "Opção desconhecida: $1"; print_help; exit 1;;
  esac
done

# ensure ssh available
ensure_pkg openssh

# helper: detect USB network interface and peer IP
detect_usb_peer_ip() {
  # check common usb network interface names and return gateway or peer ip
  for iface in usb0 rndis0 eth0 enp0s20f0u1; do
    if ip addr show dev "$iface" >/dev/null 2>&1; then
      # get network gateway or other address on interface
      # try get peer: the gateway (default via this iface)
      gw_ip=$(ip route show dev "$iface" | awk '/default/ {print $3; exit}')
      if [ -n "$gw_ip" ]; then
        echo "$gw_ip" && return 0
      fi
      # else try common other side addresses (assume .1)
      ip_prefix=$(ip -4 addr show dev "$iface" | awk '/inet /{print $2}' | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}')
      if [ -n "$ip_prefix" ]; then
        echo "${ip_prefix}.1" && return 0
      fi
    fi
  done

  # fallback: look for interfaces with "usb" in name
  for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -i usb || true); do
    gw_ip=$(ip route show dev "$iface" | awk '/default/ {print $3; exit}')
    [ -n "$gw_ip" ] && { echo "$gw_ip"; return 0; }
  done

  return 1
}

if [ -n "$IP_ARG" ]; then
  TARGET_IP="$IP_ARG"
elif [ $AUTO_DETECT -eq 1 ]; then
  echo "[*] Detectando interface USB / IP do PC..."
  TARGET_IP=$(detect_usb_peer_ip) || true
  if [ -z "$TARGET_IP" ]; then
    echo "[!] Não encontrei automaticamente. Verifique se ativou USB tethering e tente usar --ip."
    exit 1
  fi
else
  # if no arg and not auto, prompt
  read -p "Digite o IP do seu PC (ou pressione Enter para tentar detecção automática): " TARGET_IP
  if [ -z "$TARGET_IP" ]; then
    echo "[*] Tentando detecção automática..."
    TARGET_IP=$(detect_usb_peer_ip) || true
    if [ -z "$TARGET_IP" ]; then
      echo "[!] Não foi possível detectar. Rode novamente com --ip IP_DO_PC ou ative USB tethering."
      exit 1
    fi
  fi
fi

# user
if [ -z "$USER" ]; then
  read -p "Usuário no PC (ex: joao): " USER
fi
if [ -z "$USER" ]; then
  echo "Usuário não fornecido. Abortando."
  exit 1
fi

echo "[+] Alvo: $USER@$TARGET_IP:$PORT"

# if key provided and exists, use it
if [ -n "$USE_KEY" ]; then
  if [ ! -f "$USE_KEY" ]; then
    echo "[!] Chave $USE_KEY não encontrada. Abortando."
    exit 1
  fi
  echo "[*] Conectando com chave SSH..."
  ssh -o StrictHostKeyChecking=no -p "$PORT" -i "$USE_KEY" "$USER@$TARGET_IP"
  exit $?
fi

# else ask whether to use password (sshpass) or manual ssh prompt
read -p "Usar senha (s/N)? " yn
case "$yn" in
  [sS]|[yY])
    ensure_pkg sshpass
    read -sp "Senha: " PASS
    echo ""
    echo "[*] Conectando (password)..."
    # do not store password
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER@$TARGET_IP"
    exit $?
    ;;
  *)
    echo "[*] Abrindo ssh (vai pedir senha interativamente)..."
    ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER@$TARGET_IP"
    exit $?
    ;;
esac
