# dictado-wayland

**Dictado por voz para Linux con Wayland.** Presionás un atajo, hablás, lo presionás de
nuevo, y el texto aparece donde tengas el cursor: en el editor, en el navegador o en la
terminal. La transcripción la hace Whisper a través de la API de Groq, que tarda menos de
un segundo y tiene un plan gratuito.

```
Super+D  ──▶  pw-record graba el micrófono (16 kHz, mono)
              └─ notificación persistente: «🎙️ Grabando...»

Super+D  ──▶  corta la grabación
              ├─ si fue silencio, no la manda (Whisper inventa texto con el silencio)
              ├─ la manda a Whisper (whisper-large-v3-turbo, en Groq)
              ├─ copia el texto al portapapeles (wl-copy)
              └─ lo pega simulando Ctrl+V (ydotool)
```

## Por qué existe

En X11, dictar es fácil: cualquier programa puede simular que se presionan teclas. **Wayland
lo prohíbe a propósito** —que una aplicación pueda teclear en otra es un agujero de
seguridad—, y por eso la mayoría de las herramientas de dictado para Linux no funcionan en
un escritorio moderno.

La salida es [ydotool](https://github.com/ReimuNotMoe/ydotool): en lugar de pedirle permiso
al compositor, escribe los eventos de teclado directamente en `/dev/uinput`, a nivel
kernel, como si fueran de un teclado físico. Para eso necesita un daemon con permisos de
root que exponga un socket que el usuario pueda usar. Configurar eso es la parte difícil, y
el instalador la resuelve.

## Instalación

Probado en **Fedora 44 con GNOME**. Debería andar en cualquier distribución con Wayland,
PipeWire y systemd.

**1. Dependencias del sistema**

```bash
# Fedora
sudo dnf install ydotool wl-clipboard pipewire-utils libnotify python3
# Debian / Ubuntu
sudo apt install ydotool wl-clipboard pipewire-bin libnotify-bin python3-venv
```

**2. Una API key de Groq**, gratis en [console.groq.com](https://console.groq.com) → API Keys.

**3. El instalador**

```bash
git clone https://github.com/Anatsu1/dictado-wayland.git
cd dictado-wayland
./install.sh
```

Te pide la API key, instala el servicio `ydotoold` (usa `sudo` solo para eso) y registra
los dos atajos de GNOME. Se puede correr de nuevo sin romper nada.

| Opción | Para qué |
|---|---|
| `--sin-servicio` | Ya tenés `ydotoold` configurado a tu manera |
| `--sin-atajos` | No usás GNOME, o preferís crear los atajos a mano |

Para desinstalar: `./uninstall.sh`.

## Uso

| Atajo | Pega con | Para |
|---|---|---|
| **Super+D** | Ctrl+V | Casi todas las aplicaciones |
| **Super+Shift+D** | Ctrl+Shift+V | Terminales |

Lo que cuenta es el atajo con el que **terminás**: podés empezar con uno y cortar con el
otro. El texto queda además en el portapapeles, por si el pegado automático no aplica.

## Configuración

Por variables de entorno, sin tocar el código:

| Variable | Por defecto | Qué hace |
|---|---|---|
| `DICTADO_ATAJO` | `<Super>d` | Atajo principal (se lee al instalar) |
| `DICTADO_ATAJO_TERMINAL` | `<Super><Shift>d` | Atajo para terminales (se lee al instalar) |
| `DICTADO_MODELO` | `whisper-large-v3-turbo` | `whisper-large-v3` es más preciso y algo más lento |
| `DICTADO_IDIOMA` | `es` | Vacío para que Whisper lo detecte solo |
| `DICTADO_ESPERA` | `1.0` | Segundos antes de pegar; subirlo si el pegado falla a veces |
| `DICTADO_RMS_MINIMO` | `150` | Umbral de silencio; bajarlo si el micrófono es muy bajo |

Las del atajo se pasan al instalar (`DICTADO_ATAJO='<Super>v' ./install.sh`). Las demás,
como los atajos de GNOME no leen el `.bashrc`, se definen en el comando del atajo:
`env DICTADO_MODELO=whisper-large-v3 ~/.local/share/dictado/dictado-toggle.sh`.

## Si algo no anda

Primero, el log: `cat $XDG_RUNTIME_DIR/dictado.log`.

| Síntoma | Causa y arreglo |
|---|---|
| El atajo no hace nada y no hay log | El comando del atajo apunta a un archivo que no existe. Volver a correr `./install.sh`. |
| `failed to connect socket` | `ydotoold` no está corriendo: `systemctl status ydotoold`. |
| Pega en apps pero no en la terminal | Es lo esperado con Super+D: usar Super+Shift+D. |
| «No se detectó voz» hablando | Micrófono bajo: bajar `DICTADO_RMS_MINIMO`, o revisar la entrada en Configuración → Sonido. |
| «No encontré el archivo de audio» | Quedó una grabación colgada: `rm -f $XDG_RUNTIME_DIR/dictado_rec.pid && pkill pw-record` |

## Cómo está hecho

- **`dictado-toggle.sh`** — lo ejecuta el atajo. Un archivo PID decide si esta pulsación
  empieza o termina la grabación, así un solo atajo hace las dos cosas.
- **`dictado.py`** — descarta el silencio, transcribe, copia y pega.
- **`install.sh`** — dependencias, entorno de Python, API key, servicio y atajos.
- **`systemd/ydotoold.service`** — el daemon, con el socket a nombre del usuario.

**Por qué 16 kHz mono:** Whisper trabaja internamente a esa frecuencia. Grabar con más
calidad no mejora la transcripción y agranda el archivo (el límite de la API es 25 MB).

**Por qué se filtra el silencio antes de llamar a la API:** con audio vacío, Whisper no
devuelve texto vacío sino que alucina frases de sus datos de entrenamiento —«Gracias.»,
«Subtítulos realizados por la comunidad de Amara.org»—. El script mide la energía de la
grabación y, si no hay voz, ni siquiera la manda.

## Licencia

[MIT](LICENSE). La idea de partida fue el tutorial «Transcripción de Voz a Texto en Python
con API Whisper de Groq»; la adaptación a Wayland, el instalador y el filtro de silencio
son propios.
