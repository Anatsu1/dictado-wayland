#!/bin/bash
# uninstall.sh — quita el dictado. No borra la API key ni desinstala paquetes.
set -euo pipefail

DICTADO_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/dictado"

if command -v gsettings >/dev/null && gsettings list-schemas | grep -q '^org.gnome.settings-daemon.plugins.media-keys$'; then
    base=org.gnome.settings-daemon.plugins.media-keys
    ruta_base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
    lista="$(gsettings get $base custom-keybindings)"
    for id in dictado dictado-terminal; do
        gsettings reset-recursively "$base.custom-keybinding:$ruta_base/$id/"
        lista="${lista//, \'$ruta_base\/$id\/\'/}"
        lista="${lista//\'$ruta_base\/$id\/\', /}"
        lista="${lista//\'$ruta_base\/$id\/\'/}"
    done
    gsettings set $base custom-keybindings "$lista"
    echo "Atajos quitados."
fi

rm -rf "$DICTADO_HOME"
echo "Archivos quitados de $DICTADO_HOME."

if [ -f /etc/systemd/system/ydotoold.service ]; then
    echo "El servicio ydotoold sigue instalado (otras herramientas pueden usarlo). Para quitarlo:"
    echo "  sudo systemctl disable --now ydotoold && sudo rm /etc/systemd/system/ydotoold.service"
fi
echo "La API key queda en ~/.config/dictado/groq_key."
