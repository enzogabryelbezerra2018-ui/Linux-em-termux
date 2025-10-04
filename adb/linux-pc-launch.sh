#!/data/data/com.termux/files/usr/bin/env bash
# linux-pc-launch
# Uso seguro: controlar (abrir apps / iniciar VNC / rodar comando) NO SEU PC autorizado via SSH.
# NÃO use para acessar máquinas sem permissão.
set -euo pipefail

PROG="$(basename "$0")"
PORT=22
AUTO=0
IP_ARG=""
USER_ARG=""

ensure_pkg() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[+] Instalando $1..."
    pkg install -y "$1"
  fi
}

print_help() {
  cat <<-EOF
Uso: $PROG [--ip IP] [--user USER] [--port PORT] [--auto]
  --auto        tenta detectar automaticamente o IP do PC (USB tethering)
  --ip IP       especifica o IP do PC
  --user USER   usuário no PC (se não informado, será solicitado)
  --port PORT   porta SSH (padrão 22)
Exemplo:
  $PROG --auto --user meu_usuario
  $PROG --ip 192.168.42.1 --user meu_usuario
EOF
}

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0;;
    --auto) AUTO=1; shift;;
    --ip) IP_ARG="$2"; shift 2;;
    --user) USER_ARG="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    *) echo "Opção inválida: $1"; print_help; exit 1;;
  esac
done

ensure_pkg openssh
ensure_pkg sshpass

# detect usb peer ip (similar aos scripts anteriores)
detect_usb_peer_ip() {
  for iface in usb0 rndis0 eth0 enp0s20f0u1 usb1 rndis_host0; do
    if ip addr show dev "$iface" >/dev/null 2>&1; then
      gw=$(ip route show dev "$iface" | awk '/default/ {print $3; exit}')
      [ -n "$gw" ] && { echo "$gw"; return 0; }
      ipme=$(ip -4 addr show dev "$iface" | awk '/inet /{print $2}' | cut -d/ -f1)
      if [ -n "$ipme" ]; then
        prefix=$(echo "$ipme" | awk -F. '{print $1"."$2"."$3}')
        echo "${prefix}.1"
        return 0
      fi
    fi
  done
  for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -iE 'usb|rndis' || true); do
    gw=$(ip route show dev "$iface" | awk '/default/ {print $3; exit}')
    [ -n "$gw" ] && { echo "$gw"; return 0; }
  done
  return 1
}

if [ -n "${IP_ARG:-}" ]; then
  TARGET_IP="$IP_ARG"
elif [ "$AUTO" -eq 1 ]; then
  echo "[*] Detectando IP do PC via USB tethering..."
  TARGET_IP=$(detect_usb_peer_ip) || true
  if [ -z "${TARGET_IP:-}" ]; then
    echo "[!] Falha na detecção automática. Use --ip para especificar."
    exit 1
  fi
else
  read -p "IP do PC (ou ENTER para detecção automática): " TARGET_IP
  if [ -z "$TARGET_IP" ]; then
    echo "[*] Tentando detecção automática..."
    TARGET_IP=$(detect_usb_peer_ip) || true
    if [ -z "${TARGET_IP:-}" ]; then
      echo "[!] Não consegui detectar automaticamente. Rode novamente com --ip ou --auto."
      exit 1
    fi
  fi
fi

if [ -z "${USER_ARG:-}" ]; then
  read -p "Usuário no PC: " USER_ARG
fi
if [ -z "${USER_ARG:-}" ]; then
  echo "Usuário não informado. Abortando."
  exit 1
fi

echo "[+] Alvo: $USER_ARG@$TARGET_IP:$PORT"
echo "Digite 'q' ou 'quit' no prompt de senha para cancelar."

# função de teste de autenticação
test_auth() {
  local pw="$1"
  sshpass -p "$pw" ssh -o BatchMode=no -o StrictHostKeyChecking=no -o ConnectTimeout=8 \
    -p "$PORT" "$USER_ARG@$TARGET_IP" 'echo __SSH_OK__' 2>/dev/null | grep -q '__SSH_OK__'
  return $?
}

# loop de senha até acertar ou cancelar
PASSWORD=""
while true; do
  printf "key: "
  IFS= read -r -s PASSWORD
  echo
  if [ "$PASSWORD" = "q" ] || [ "$PASSWORD" = "quit" ]; then
    echo "[*] Cancelado."
    exit 0
  fi
  if [ -z "$PASSWORD" ]; then
    echo "[!] Senha vazia, tente novamente (ou digite 'q')."
    continue
  fi
  echo "[*] Testando autenticação..."
  if test_auth "$PASSWORD"; then
    echo "[✔] Autenticado com sucesso."
    break
  else
    echo "[✖] Autenticação falhou. Senha incorreta ou conexão indisponível."
    echo "Tente novamente (ou digite 'q' para sair)."
  fi
done

# menu de ações
cat <<-MENU

Escolha a ação:
  1) Abrir um aplicativo/janela NO COMPUTADOR (abre na tela fisica do PC)
  2) Iniciar VNC no PC (se vncserver instalado) e informar como conectar
  3) Executar um comando remoto qualquer (rodar/sair)
  4) Abrir um shell SSH interativo no PC
  0) Sair
MENU

read -p "Opção: " OPT
case "$OPT" in
  1)
    read -p "Comando do app (ex: gedit, firefox, code, nautilus): " REMOTE_CMD
    if [ -z "$REMOTE_CMD" ]; then
      echo "Comando vazio. Abortando."
      exit 1
    fi
    # tenta executar no display :0 (tela física). usa nohup para não depender do ssh
    echo "[*] Executando no PC: DISPLAY=:0 nohup $REMOTE_CMD &"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER_ARG@$TARGET_IP" \
      "DISPLAY=:0 nohup $REMOTE_CMD >/dev/null 2>&1 &" && echo "[✔] Comando enviado."
    ;;
  2)
    # Inicia vncserver :1 no PC e informa porta 5901
    read -p "Resolução VNC (padrão 1280x720): " VRES
    VRES=${VRES:-1280x720}
    echo "[*] Iniciando vncserver no PC (:1, resolução $VRES)..."
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER_ARG@$TARGET_IP" \
      "vncserver -geometry $VRES -depth 24 :1 >/dev/null 2>&1 && echo __VNC_OK__ || echo __VNC_FAIL__" \
      | while read -r line; do
          if [ "$line" = "__VNC_OK__" ]; then
            echo "[✔] VNC iniciado no PC em :1 (porta 5901). Conecte com um cliente VNC ao:"
            echo "    $TARGET_IP:5901"
          else
            echo "[!] Falha ao iniciar VNC. Verifique se 'vncserver' está instalado no PC."
          fi
        done
    ;;
  3)
    read -p "Comando remoto a executar: " RCMD
    if [ -z "$RCMD" ]; then echo "Comando vazio. Abortando."; exit 1; fi
    echo "[*] Executando: $RCMD"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER_ARG@$TARGET_IP" "$RCMD"
    ;;
  4)
    echo "[*] Abrindo shell SSH interativo..."
    exec ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER_ARG@$TARGET_IP"
    ;;
  0)
    echo "Saindo."
    exit 0
    ;;
  *)
    echo "Opção inválida. Saindo."
    exit 1
    ;;
esac

exit 0
