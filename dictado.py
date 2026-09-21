"""
dictado.py — transcribe un WAV con Whisper (Groq), lo copia al portapapeles
y lo pega donde esté el cursor.

Uso: dictado.py <audio.wav> [terminal]

La API key se lee de GROQ_API_KEY o, si no existe (los atajos de GNOME no
cargan el .bashrc), de ~/.config/dictado/groq_key.
"""

import array
import os
import subprocess
import sys
import time
import wave
from pathlib import Path

MODELO = os.environ.get("DICTADO_MODELO", "whisper-large-v3-turbo")
IDIOMA = os.environ.get("DICTADO_IDIOMA", "es") or None
# Segundos de espera antes de pegar, para que se suelten las teclas del atajo.
ESPERA_PEGADO = float(os.environ.get("DICTADO_ESPERA", "1.0"))

# Por debajo de esto no se manda nada a la API: Whisper, ante el silencio,
# no devuelve vacío sino que inventa ("Gracias.", "Subtítulos por…").
DURACION_MINIMA = 0.4  # segundos
# Sobre 32768. El ruido de fondo de un micrófono ronda 20-80 y la voz pasa
# holgada los 500; con un micrófono muy bajo, bajarlo con DICTADO_RMS_MINIMO.
RMS_MINIMO = int(os.environ.get("DICTADO_RMS_MINIMO", "150"))

# Frases que Whisper alucina con audio casi vacío. Si la transcripción es
# exactamente una de estas, se descarta.
ALUCINACIONES = {
    "gracias.",
    "gracias por ver el video.",
    "¡gracias por ver el video!",
    "subtítulos realizados por la comunidad de amara.org",
    "thank you.",
    "thanks for watching!",
}

ARCHIVO_KEY = Path.home() / ".config" / "dictado" / "groq_key"


def notificar(mensaje):
    subprocess.run(["notify-send", "-t", "3000", "🎙️ Dictado", mensaje])


def obtener_api_key():
    key = os.environ.get("GROQ_API_KEY")
    if key:
        return key.strip()
    if ARCHIVO_KEY.exists():
        return ARCHIVO_KEY.read_text().strip()
    return None


def hay_voz(ruta):
    """Descarta grabaciones demasiado cortas o que son solo ruido de fondo."""
    with wave.open(str(ruta), "rb") as w:
        if w.getsampwidth() != 2:
            return True  # formato inesperado: mejor dejar que decida la API
        cuadros = w.readframes(w.getnframes())
        duracion = w.getnframes() / w.getframerate()
    if duracion < DURACION_MINIMA:
        return False
    muestras = array.array("h", cuadros)
    if not muestras:
        return False
    rms = (sum(m * m for m in muestras) / len(muestras)) ** 0.5
    return rms >= RMS_MINIMO


def transcribir(ruta, api_key):
    from groq import Groq  # import diferido: el chequeo de silencio no lo necesita

    client = Groq(api_key=api_key)
    with open(ruta, "rb") as f:
        resultado = client.audio.transcriptions.create(
            file=(os.path.basename(ruta), f.read()),
            model=MODELO,
            language=IDIOMA,
            response_format="text",
        )
    texto = resultado if isinstance(resultado, str) else resultado.text
    return texto.strip()


def pegar(texto, modo):
    subprocess.run(["wl-copy"], input=texto.encode())
    time.sleep(ESPERA_PEGADO)
    # Códigos de tecla de Linux: 29 = Ctrl, 42 = Shift, 47 = V
    if modo == "terminal":
        teclas = ["29:1", "42:1", "47:1", "47:0", "42:0", "29:0"]
    else:
        teclas = ["29:1", "47:1", "47:0", "29:0"]
    return subprocess.run(["ydotool", "key", *teclas], capture_output=True, text=True)


def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        notificar("❌ No encontré el archivo de audio")
        sys.exit(1)
    ruta = sys.argv[1]
    modo = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        if not hay_voz(ruta):
            notificar("⚠️ No se detectó voz")
            return

        api_key = obtener_api_key()
        if not api_key:
            notificar(f"❌ Falta la API key ({ARCHIVO_KEY})")
            sys.exit(1)

        try:
            texto = transcribir(ruta, api_key)
        except Exception as e:
            notificar(f"❌ Error de transcripción: {e}")
            sys.exit(1)
    finally:
        os.unlink(ruta)

    if not texto or texto.lower() in ALUCINACIONES:
        notificar("⚠️ No se detectó voz")
        return

    resultado = pegar(texto, modo)
    if resultado.returncode == 0:
        notificar(f"✅ {texto[:80]}")
    else:
        notificar(f"❌ ydotool falló: {resultado.stderr[:100]} — el texto quedó en el portapapeles")


if __name__ == "__main__":
    main()
