#!/bin/bash
# install.sh — instala el dictado por voz para el usuario actual.
#
#   ./install.sh                 instalación completa
#   ./install.sh --sin-servicio  no toca systemd (ydotoold ya configurado a mano)
#   ./install.sh --sin-atajos    no registra los atajos de GNOME
#
# Variables opcionales:
#   DICTADO_ATAJO            atajo para pegar en apps     (por defecto <Super>d)
#   DICTADO_ATAJO_TERMINAL   atajo para pegar en terminal (por defecto <Super><Shift>d)
set -euo pipefail

ORIGEN="$(cd "$(dirname "$0")" && pwd)"
DICTADO_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/dictado"
ARCHIVO_KEY="$HOME/.config/dictado/groq_key"
ATAJO="${DICTADO_ATAJO:-<Super>d}"
ATAJO_TERMINAL="${DICTADO_ATAJO_TERMINAL:-<Super><Shift>d}"

CON_SERVICIO=1
CON_ATAJOS=1
for arg in "$@"; do
    case "$arg" in
        --sin-servicio) CON_SERVICIO=0 ;;
        --sin-atajos)   CON_ATAJOS=0 ;;
        *) echo "Opción desconocida: $arg" >&2; exit 2 ;;
    esac
done

paso() { printf '\n\033[1;32m▸ %s\033[0m\n' "$1"; }
aviso() { printf '\033[1;33m  %s\033[0m\n' "$1"; }

# --- 1. Dependencias ---------------------------------------------------------
paso "Dependencias"
faltan=()
for cmd in pw-record wl-copy ydotool ydotoold notify-send python3; do
    command -v "$cmd" >/dev/null || faltan+=("$cmd")
done
if [ ${#faltan[@]} -gt 0 ]; then
    echo "  Faltan: ${faltan[*]}"
    if command -v dnf >/dev/null; then
        echo "  Instalalas con: sudo dnf install ydotool wl-clipboard pipewire-utils libnotify python3"
    elif command -v apt >/dev/null; then
        echo "  Instalalas con: sudo apt install ydotool wl-clipboard pipewire-bin libnotify-bin python3-venv"
    fi
    exit 1
fi
echo "  Todo presente."

# --- 2. Archivos y entorno de Python ------------------------------------------
paso "Archivos en $DICTADO_HOME"
mkdir -p "$DICTADO_HOME"
install -m 755 "$ORIGEN/dictado-toggle.sh" "$DICTADO_HOME/dictado-toggle.sh"
install -m 644 "$ORIGEN/dictado.py" "$DICTADO_HOME/dictado.py"
if [ ! -x "$DICTADO_HOME/venv/bin/python" ]; then
    python3 -m venv "$DICTADO_HOME/venv"
fi
"$DICTADO_HOME/venv/bin/pip" install --quiet --upgrade groq
echo "  Listo."

# --- 3. API key de Groq --------------------------------------------------------
paso "API key de Groq"
if [ -s "$ARCHIVO_KEY" ] || [ -n "${GROQ_API_KEY:-}" ]; then
    echo "  Ya configurada."
else
    echo "  Se crea gratis en https://console.groq.com → API Keys."
    read -rsp "  Pegala acá (no se muestra): " key; echo
    mkdir -p "$(dirname "$ARCHIVO_KEY")"
    ( umask 077; printf '%s\n' "$key" > "$ARCHIVO_KEY" )
    echo "  Guardada en $ARCHIVO_KEY (permisos 600)."
fi

# --- 4. ydotoold ---------------------------------------------------------------
# Wayland no deja que una aplicación simule teclas. ydotool lo resuelve
# escribiendo en /dev/uinput, a nivel kernel, y para eso necesita un daemon
# con permisos de root que exponga un socket que el usuario pueda usar.
paso "Servicio ydotoold"
if [ "$CON_SERVICIO" -eq 0 ]; then
    aviso "Salteado (--sin-servicio)."
elif systemctl is-active --quiet ydotoold; then
    echo "  Ya está activo."
else
    tmp="$(mktemp)"
    sed -e "s|--socket-own=UID:GID|--socket-own=$(id -u):$(id -g)|" \
        -e "s|/usr/bin/ydotoold|$(command -v ydotoold)|" \
        "$ORIGEN/systemd/ydotoold.service" > "$tmp"
    echo "  Hace falta sudo para instalar el servicio de systemd."
    sudo install -m 644 "$tmp" /etc/systemd/system/ydotoold.service
    rm -f "$tmp"
    # El servicio que trae el paquete crea el socket como root y compite por
    # /dev/uinput: se apaga para que no haya dos daemons.
    sudo systemctl disable --now ydotool.service 2>/dev/null || true
    sudo systemctl daemon-reload
    sudo systemctl enable --now ydotoold.service
    echo "  Activo."
fi

# --- 5. Atajos de GNOME ----------------------------------------------------------
paso "Atajos de teclado"
if [ "$CON_ATAJOS" -eq 0 ]; then
    aviso "Salteado (--sin-atajos)."
elif ! command -v gsettings >/dev/null || ! gsettings list-schemas | grep -q '^org.gnome.settings-daemon.plugins.media-keys$'; then
    aviso "No es GNOME: creá a mano dos atajos que ejecuten"
    aviso "  $DICTADO_HOME/dictado-toggle.sh"
    aviso "  $DICTADO_HOME/dictado-toggle.sh terminal"
else
    base=org.gnome.settings-daemon.plugins.media-keys
    ruta_base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
    lista="$(gsettings get $base custom-keybindings)"

    registrar() {  # id, nombre, comando, atajo
        local ruta="$ruta_base/$1/"
        local esquema="$base.custom-keybinding:$ruta"
        gsettings set "$esquema" name "$2"
        gsettings set "$esquema" command "$3"
        gsettings set "$esquema" binding "$4"
        if [[ "$lista" != *"'$ruta'"* ]]; then
            if [[ "$lista" == "@as []" || "$lista" == "[]" ]]; then
                lista="['$ruta']"
            else
                lista="${lista%]}, '$ruta']"
            fi
        fi
    }
    registrar dictado "Dictado" "$DICTADO_HOME/dictado-toggle.sh" "$ATAJO"
    registrar dictado-terminal "Dictado (terminal)" "$DICTADO_HOME/dictado-toggle.sh terminal" "$ATAJO_TERMINAL"
    gsettings set $base custom-keybindings "$lista"
    echo "  $ATAJO → pega en aplicaciones · $ATAJO_TERMINAL → pega en terminales"
fi

paso "Listo"
echo "  Presioná $ATAJO, hablá, y volvé a presionarlo."
echo "  Si algo falla: cat \${XDG_RUNTIME_DIR:-/tmp}/dictado.log"
