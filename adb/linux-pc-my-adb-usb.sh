#!/data/data/com.termux/files/usr/bin/env bash
# linux-pc-my-adb-usb
# Detecta PC via USB tethering e abre tela do PC via VNC (requer VNC server no PC).
# Uso: bash ~/linux-pc-my-adb-usb [--ip IP] [--port PORT]
# Exemplo: bash ~/linux-pc-my-adb-usb --auto
set -euo pipefail

PROG="$(basename "$0")"
PORT=5901
AUTO=0
IP_ARG=""

usage(){
  cat <<-US
Uso: $PROG [--ip IP] [--port PORT] [--auto]
  --auto    tenta detectar automaticamente o IP do PC via USB tethering
  --ip IP   especifica o IP do PC (p.ex. 192.168.42.1)
  --port P  porta VNC (padrão 5901)
Exemplo:
  $PROG --auto
  $PROG --ip 192.168.42.1
US
}

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --auto) AUTO=1; shift;;
    --ip) IP_ARG="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --help|-h) usage; exit 0;;
    *) echo "Opção inválida: $1"; usage; exit 1;;
  esac
done

# detect common usb network interfaces and derive peer IP
detect_usb_peer_ip(){
  for iface in usb0 rndis0 rndis_host0 eth0 enp0s20f0u1 usb1; do
    if ip addr show dev "$iface" >/dev/null 2>&1; then
      # tenta rota default ligada a essa interface
      gw=$(ip route show dev "$iface" 2>/dev/null | awk '/default/ {print $3; exit}')
      if [ -n "$gw" ]; then
        echo "$gw" && return 0
      fi
      # tenta usar prefix + .1
      ipme=$(ip -4 addr show dev "$iface" | awk '/inet /{print $2}' | cut -d/ -f1)
      if [ -n "$ipme" ]; then
        prefix=$(echo "$ipme" | awk -F. '{print $1"."$2"."$3}')
        echo "${prefix}.1" && return 0
      fi
    fi
  done
  # tentativa genérica: procura interfaces com "usb" ou "rndis"
  for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -iE 'usb|rndis' || true); do
    gw=$(ip route show dev "$iface" 2>/dev/null | awk '/default/ {print $3; exit}')
    [ -n "$gw" ] && { echo "$gw"; return 0; }
  done
  return 1
}

if [ -n "${IP_ARG}" ]; then
  TARGET_IP="$IP_ARG"
elif [ "$AUTO" -eq 1 ]; then
  echo "[*] Detectando IP do PC (USB tethering)..."
  TARGET_IP=$(detect_usb_peer_ip) || true
  if [ -z "${TARGET_IP:-}" ]; then
    echo "[!] Falha na detecção automática. Use --ip IP_DO_PC."
    exit 1
  fi
else
  read -p "IP do PC (ENTER para tentar detecção automática): " TARGET_IP
  if [ -z "$TARGET_IP" ]; then
    echo "[*] Tentando detecção automática..."
    TARGET_IP=$(detect_usb_peer_ip) || true
    if [ -z "${TARGET_IP:-}" ]; then
      echo "[!] Não consegui detectar. Use --ip IP_DO_PC ou ative USB tethering."
      exit 1
    fi
  fi
fi

echo "[+] Alvo: $TARGET_IP:$PORT"
# verifica se a porta está aberta (timeout curto)
if command -v nc >/dev/null 2>&1; then
  nc -z -w 3 "$TARGET_IP" "$PORT" >/dev/null 2>&1
  OK=$?
else
  # fallback usando bash/tcp connect
  timeout_cmd() {
    (echo >/dev/tcp/"$1"/"$2") >/dev/null 2>&1 && return 0 || return 1
  }
  if timeout_cmd "$TARGET_IP" "$PORT"; then
    OK=0
  else
    OK=1
  fi
fi

if [ "$OK" -ne 0 ]; then
  echo "[!] Porta $PORT não acessível em $TARGET_IP. Verifique se o VNC server no PC está rodando."
  echo "Dicas rápidas:"
  echo " - No PC rode: vncserver :1"
  echo " - Verifique firewall no PC (porta 5901 aberta)"
  echo " - Se estiver usando ADB (sem tethering) veja notas abaixo"
  exit 1
fi

# Tentar abrir um app VNC no Android via URI vnc:// se houver
VNC_URI="vnc://$TARGET_IP:$(($PORT - 5900 + 5900))"  # mantém formato padrão (5901)
echo "[*] Abrindo cliente VNC (se houver um app registrado para vnc:// )..."
# usa termux-open para abrir o app de VNC instalado (se houver)
if command -v termux-open >/dev/null 2>&1; then
  termux-open "$VNC_URI" && exit 0 || true
fi

# fallback: só imprime as instruções para conectar manualmente
echo "[✔] Porta VNC acessível. Conecte com um cliente VNC no Android para:"
echo "    Endereço: $TARGET_IP:$PORT"
echo "    (Ex.: no bVNC ou VNC Viewer coloque $TARGET_IP e porta $PORT)"
exit 0
