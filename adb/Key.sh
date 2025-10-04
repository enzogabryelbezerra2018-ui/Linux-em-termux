#!/data/data/com.termux/files/usr/bin/env bash
# key-linux-termux
# Loop de senha: pede 'key:' e tenta conectar via SSH até a senha correta ser informada.
# Uso legal: conectar ao SEU PC com cabo USB / tethering / rede local.
# NÃO usar para acessar máquinas sem autorização.

set -euo pipefail

PROG="$(basename "$0")"

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
  --ip IP       especifica o IP do PC diretamente
  --user USER   usuário no PC (se não informado, será solicitado)
  --port PORT   porta SSH (padrão 22)
Exemplo:
  $PROG --auto --user meu_usuario
  $PROG --ip 192.168.42.1 --user meu_usuario
EOF
}

# defaults
PORT=22
AUTO=0
IP_ARG=""
USER_ARG=""

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

# pacotes necessários
ensure_pkg openssh

# função simples de detecção (tenta usb0, rndis0, etc)
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
  # fallback: tentar qualquer interface com usb/rndis no nome
  for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -iE 'usb|rndis' || true); do
    gw=$(ip route show dev "$iface" | awk '/default/ {print $3; exit}')
    [ -n "$gw" ] && { echo "$gw"; return 0; }
  done
  return 1
}

# obter target IP
if [ -n "$IP_ARG" ]; then
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

# usuário
if [ -z "${USER_ARG:-}" ]; then
  read -p "Usuário no PC: " USER_ARG
fi
if [ -z "${USER_ARG:-}" ]; then
  echo "Usuário não informado. Abortando."
  exit 1
fi

echo "[+] Alvo: $USER_ARG@$TARGET_IP:$PORT"
echo "Digite 'q' ou 'quit' para cancelar a qualquer momento."

# instala sshpass apenas se for necessário (somente para uso momentâneo)
ensure_pkg sshpass

# função que tenta conectar com a senha dada; retorna 0 se sucesso
try_ssh_with_password() {
  local pw="$1"
  # tenta rodar um comando simples remoto pra testar autenticação sem abrir shell interativo
  # -o ConnectTimeout=8 para não travar muito tempo
  # usamos sshpass para enviar a senha, e checamos o código de saída
  sshpass -p "$pw" ssh -o BatchMode=no -o StrictHostKeyChecking=no \
    -o ConnectTimeout=8 -p "$PORT" "$USER_ARG@$TARGET_IP" 'echo __SSH_OK__' 2>/dev/null | grep -q '__SSH_OK__'
  return $?
}

# loop de senha
while true; do
  # prompt com "key:" e sem eco
  printf "key: "
  # ler senha sem eco
  IFS= read -r -s PASSWORD
  echo

  # permitir cancelar digitando 'q' ou 'quit'
  if [ "$PASSWORD" = "q" ] || [ "$PASSWORD" = "quit" ]; then
    echo "[*] Cancelado pelo usuário."
    exit 0
  fi

  if [ -z "$PASSWORD" ]; then
    echo "[!] Senha vazia — digite a senha correta ou 'q' para sair."
    continue
  fi

  echo "[*] Tentando autenticar..."
  if try_ssh_with_password "$PASSWORD"; then
    echo "[✔] Autenticado com sucesso! Abrindo sessão SSH interativa..."
    # abrir sessão SSH real (sem mostrar senha)
    # usamos exec para substituir o processo atual pelo ssh (assim Ctrl+D fecha)
    exec ssh -o StrictHostKeyChecking=no -p "$PORT" "$USER_ARG@$TARGET_IP"
    # não chegamos aqui se exec funcionar
    exit 0
  else
    echo "[✖] Autenticação falhou — senha incorreta OU conexão não disponível."
    echo "Tente novamente (digite 'q' para cancelar)."
    # loop continua pedindo a senha novamente
  fi
done
