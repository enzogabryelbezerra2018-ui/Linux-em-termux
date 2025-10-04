#!/data/data/com.termux/files/usr/bin/env bash
# ===========================================
# Script: run-linux.sh
# Autor: Enzo & GPT-5
# Descrição: Executor automático de Linux no Termux
# ===========================================

set -e

DISTRO="debian"        # Pode mudar pra ubuntu, fedora, etc.
USER_NAME="user"       # Usuário dentro do Linux
VNC_RESOLUTION="1280x720"
PORT="5901"

# -------------------------------
# Funções
# -------------------------------

banner() {
  clear
  echo "===================================="
  echo "  🐧 Linux Launcher for Termux"
  echo "===================================="
  echo ""
}

check_deps() {
  for pkg in proot-distro pulseaudio; do
    if ! command -v $pkg >/dev/null 2>&1; then
      echo "[+] Instalando dependência: $pkg"
      pkg install -y $pkg
    fi
  done
}

check_distro() {
  if ! proot-distro list | grep -q "$DISTRO"; then
    echo "[x] Nenhuma distro encontrada. Instalando Debian automaticamente..."
    proot-distro install $DISTRO
  fi
}

launch_linux() {
  echo "[+] Iniciando Linux ($DISTRO)..."
  echo ""
  proot-distro login $DISTRO --shared-tmp --bind /sdcard
}

start_vnc() {
  echo "[+] Iniciando Linux com servidor VNC..."
  proot-distro login $DISTRO -- bash -lc "su - $USER_NAME -c 'vncserver -geometry $VNC_RESOLUTION -depth 24 :1'"
  echo "[✔] VNC iniciado! Conecte-se a IP_DO_CELULAR:$PORT"
}

show_help() {
  echo "Uso: bash run-linux.sh [opção]"
  echo ""
  echo "Opções:"
  echo "  --vnc      Inicia Linux e sobe o servidor gráfico VNC"
  echo "  --shell    Entra no Linux pelo terminal (padrão)"
  echo "  --stopvnc  Encerra o servidor VNC"
  echo "  --help     Mostra esta ajuda"
  echo ""
}

stop_vnc() {
  echo "[+] Encerrando servidor VNC..."
  proot-distro login $DISTRO -- bash -lc "su - $USER_NAME -c 'vncserver -kill :1'"
  echo "[✔] VNC parado."
}

# -------------------------------
# Execução
# -------------------------------

banner
check_deps
check_distro

case "$1" in
  --vnc)
    start_vnc
    ;;
  --shell|"")
    launch_linux
    ;;
  --stopvnc)
    stop_vnc
    ;;
  --help|-h)
    show_help
    ;;
  *)
    echo "Opção desconhecida: $1"
    show_help
    ;;
esac
