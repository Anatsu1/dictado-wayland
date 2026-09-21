#!/bin/bash
# dictado-toggle.sh — lo ejecuta el atajo de teclado.
# Primera pulsación: empieza a grabar (notificación persistente).
# Segunda pulsación: corta, transcribe y pega el texto.
#
# Uso: dictado-toggle.sh            -> pega con Ctrl+V
#      dictado-toggle.sh terminal   -> pega con Ctrl+Shift+V
#
# Los atajos de GNOME corren con un entorno mínimo (sin .bashrc), así que
# todo lo que el script necesita se define acá.

DICTADO_HOME="${DICTADO_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/dictado}"
export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-/run/ydotoold/socket}"

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="$RUNTIME/dictado_rec.pid"
AUDIO="$RUNTIME/dictado_rec.wav"
NOTIFID="$RUNTIME/dictado_notif.id"
LOG="$RUNTIME/dictado.log"

exec >> "$LOG" 2>&1

if [ -f "$PIDFILE" ]; then
    # Está grabando -> cortar y transcribir
    kill -TERM "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    sleep 0.3   # deja que pw-record cierre el archivo

    # Reemplaza la notificación persistente por una que expira sola
    ID=$(cat "$NOTIFID" 2>/dev/null)
    notify-send ${ID:+-r "$ID"} -t 2000 "🎙️ Dictado" "Transcribiendo..."

    "$DICTADO_HOME/venv/bin/python" "$DICTADO_HOME/dictado.py" "$AUDIO" "$1"
else
    # No está grabando -> empezar. Whisper trabaja a 16 kHz mono: grabar con
    # más calidad no mejora la transcripción y agranda el archivo.
    pw-record --rate=16000 --channels=1 "$AUDIO" &
    echo $! > "$PIDFILE"
    notify-send -p -u critical "🎙️ Grabando..." "Presioná el atajo de nuevo para terminar" > "$NOTIFID"
fi
