"""
Neu_to_text_new5.py
Convierte señales del Unicorn Hybrid Black en señales para el juego de Godot
("A rocky tower", autoload BrainLink) e imprime en la terminal lo que detecta.

Mecánicas (palabra UDP / tecla -> acción por defecto en el juego):
  - Parpadeo voluntario (pico a pico en Fz, detección de Neuro_a_tecla_funciona_mandibula)
        -> BLINK / B (girar), mensaje "Parpadeo".
  - Negación con la cabeza (giroscopio, eje de giro izquierda/derecha)
        -> SHAKE / N (andar / parar), mensaje "Cabeza".
  - Asentir con la cabeza (giroscopio, eje de cabeceo arriba/abajo)
        -> NOD / Y (espada), mensaje "Muerde", con cooldown de 2 s.
Cada gesto envía UNA señal: hay que parar (1 s sin movimiento) antes de que el
mismo gesto vuelva a contar.

Por defecto envía la palabra por UDP al puerto del juego (no hace falta que la
ventana del juego tenga el foco). Cada segundo envía además "HELLO BLINK SHAKE
NOD": el juego activa solo su interfaz cerebral al recibirlo y muestra
"Headset connected". Las acciones se cambian en Settings > Brain interface.
Si el casco se desconecta (Bluetooth), el script reintenta solo cada 3 s.

Lo más fácil: doble clic en tools/unicorn_start.bat (instala numpy si falta).
UnicornPy se busca solo: en UNICORN_PY_PATH, junto a este script, en la
instalación de Unicorn Suite (Documentos\\gtec\\Unicorn Suite\\...) y en
carpetas cercanas de Documentos, Escritorio y Descargas.

Uso (desde la terminal de Visual Studio / VS Code):
    python Neu_to_text_new5.py --test --debug     # Solo imprime, NO envía nada
    python Neu_to_text_new5.py --test             # Solo imprime mensajes
    python Neu_to_text_new5.py                    # Envía BLINK/SHAKE/NOD por UDP a 127.0.0.1:1000
    python Neu_to_text_new5.py --host 192.168.1.20 --port 1000   # Juego en otro PC
    python Neu_to_text_new5.py --keys             # Presiona B/N/Y (pynput, juego enfocado)
"""

import argparse
import os
import socket
import sys
import time
from pathlib import Path

import numpy as np

try:
    from pynput.keyboard import Controller
except ImportError:
    Controller = None


def unicorn_candidates():
    """Carpetas donde puede estar UnicornPy.pyd, en orden de preferencia."""
    here = Path(__file__).resolve().parent
    candidates = []
    if os.environ.get("UNICORN_PY_PATH"):
        candidates.append(Path(os.environ["UNICORN_PY_PATH"]))
    candidates += [here, here / "Lib"]
    home = Path.home()
    documents = [home / "Documents", home / "Documentos",
                 home / "OneDrive" / "Documents", home / "OneDrive" / "Documentos"]
    # Instalación estándar de Unicorn Suite.
    for docs in documents:
        suite = docs / "gtec" / "Unicorn Suite"
        if suite.is_dir():
            candidates += sorted(p.parent for p in suite.rglob("UnicornPy.pyd"))
    # Copias a mano (p. ej. Documentos\Hackagame\UnicornPy.pyd), hasta 2 niveles.
    nearby = documents + [home / "Desktop", home / "Escritorio", home / "OneDrive" / "Desktop",
                          home / "OneDrive" / "Escritorio", home / "Downloads", home / "Descargas"]
    for base in nearby:
        if base.is_dir():
            for pattern in ("UnicornPy.pyd", "*/UnicornPy.pyd", "*/*/UnicornPy.pyd"):
                candidates += sorted(p.parent for p in base.glob(pattern))
    return candidates


def add_unicorn_paths():
    """Pone primero en sys.path la carpeta con UnicornPy.pyd, para no tener que
    configurar PYTHONPATH. Devuelve la carpeta, o None si no hay ninguna."""
    for folder in unicorn_candidates():
        if (folder / "UnicornPy.pyd").is_file():
            sys.path.insert(0, str(folder))
            # Unicorn.dll y Gtec.Licensing.Unicorn.dll están en la misma carpeta.
            if hasattr(os, "add_dll_directory"):
                os.add_dll_directory(str(folder))
            return folder
    return None


UNICORNPY_FOLDER = add_unicorn_paths()

# UnicornPy lanza DeviceException("No License Found") al importarse si no hay
# licencia: añádela en Unicorn Suite Hybrid Black -> Licenses -> Add License.
UNICORNPY_ERROR = None
try:
    import UnicornPy
except Exception as exc:
    UnicornPy = None
    UNICORNPY_ERROR = exc

# -----------------------------------------------------------------------------
# MAPPING DE CANALES UNICORN HYBRID BLACK (8 EEG + Sensores)
# -----------------------------------------------------------------------------
# Índice 0  = Fz  --> Parpadeo (EOG)
# Índice 1-7 = C3, Cz, C4, Pz, P1, P2, Oz  --> IGNORADOS (ya no se usa el Alfa)
# Índice 8-10  = Acelerómetro X, Y, Z
# Índice 11-13 = Giroscopio X, Y, Z (grados/s)  --> Movimientos de cabeza
# Índice 14 = Batería | 15 = Contador | 16 = Indicador de validación
CH_FRONTAL = 0
CH_GYRO = slice(11, 14)

# Ejes del giroscopio. No tengo datos de giroscopio para confirmarlos: usa
# --debug, niega con la cabeza y luego asiente, y mira qué eje (X/Y/Z) sube en
# cada caso. Si no coinciden con estos valores, cámbialos aquí (11, 12 o 13).
CH_GYRO_YAW = 13    # Negación (izquierda/derecha)
CH_GYRO_PITCH = 12  # Asentir (arriba/abajo)

# -----------------------------------------------------------------------------
# CONFIGURACIÓN DE TECLAS Y UMBRALES
# -----------------------------------------------------------------------------
# Palabras UDP y teclas que el juego reconoce (scripts/settings.gd, SIGNALS).
WORD_BLINK = 'BLINK'
WORD_HEAD_SHAKE = 'SHAKE'
WORD_ATTACK = 'NOD'
KEY_BLINK = 'b'
KEY_HEAD_SHAKE = 'n'
KEY_ATTACK = 'y'

GAME_HOST = '127.0.0.1'
GAME_PORT = 1000
HELLO_INTERVAL_SEC = 1.0  # El juego da el casco por desconectado tras 3 s sin HELLO
RECONNECT_DELAY_SEC = 3.0

# Parpadeo: pico a pico de Fz suavizado, en los últimos BLINK_WINDOW_SEC.
# El suavizado (media de 100 ms) anula 10, 20... 50 y 60 Hz: el zumbido de la
# red eléctrica y el ritmo alfa ya no parecen parpadeos.
BLINK_THRESHOLD = 120.0      # µV
BLINK_WINDOW_SEC = 0.25      # Cubre la subida de un parpadeo; dos parpadeos a 0.6 s cuentan dos
BLINK_SMOOTH_SAMPLES = 25    # 100 ms a 250 Hz
BLINK_REARM_FRACTION = 0.6   # Vuelve a contar cuando baja del 60 % del umbral
BLINK_COOLDOWN_SEC = 0.5
# Mover la cabeza mueve los electrodos y da picos en Fz: no se cuentan
# parpadeos mientras el giroscopio pase de esto (grados/s).
BLINK_MOTION_GATE = 40.0

# Movimientos de cabeza: oscilación del giroscopio (grados/s). El giroscopio
# mide velocidad: negar izq-der-izq = 2 cambios de sentido; asentir (abajo y de
# vuelta arriba) = 1 cambio de sentido.
GYRO_THRESHOLD = 80.0          # Cada vaivén debe superar este valor (en ambos sentidos)
SHAKE_MIN_REVERSALS = 2
NOD_MIN_REVERSALS = 1
HEAD_SHAKE_COOLDOWN_SEC = 1.2
ATTACK_COOLDOWN_SEC = 2.0      # Tiempo mínimo entre ataques

# Intervalo para imprimir valores en modo --debug
DEBUG_PRINT_INTERVAL_SEC = 0.5


class HeadsetError(Exception):
    """El casco no está disponible (apagado, sin emparejar, en uso...)."""


# -----------------------------------------------------------------------------
# FILTROS DIGITALES (DSP)
# -----------------------------------------------------------------------------
def count_reversals(signal, threshold):
    """Cuenta los cambios de sentido entre vaivenes que superan el umbral.

    Solo se consideran las muestras con |valor| > threshold; después se cuentan
    las veces que el signo cambia. Ida-vuelta-ida = 2 cambios.
    """
    strong = signal[np.abs(signal) > threshold]
    if strong.size < 2:
        return 0
    return int(np.count_nonzero(np.diff(np.sign(strong))))


def smoothed(signal, samples):
    """Media móvil: solo las muestras completas (len(signal) - samples + 1)."""
    return np.convolve(signal, np.ones(samples) / samples, mode="valid")


# -----------------------------------------------------------------------------
# DETECCIÓN
# -----------------------------------------------------------------------------
class Detector:
    """Decide, con la ventana de 1 s más reciente, qué gestos se han hecho."""

    def __init__(self, sampling_rate):
        self.blink_samples = int(BLINK_WINDOW_SEC * sampling_rate)
        self.last_blink = -1e9
        self.last_shake = -1e9
        self.last_attack = -1e9   # Permite el primer ataque de inmediato
        # Cada gesto se rearma cuando su señal vuelve a estar tranquila.
        self.blink_armed = True
        self.shake_armed = True
        self.nod_armed = True
        self.debug = {}

    def update(self, window, now):
        """Devuelve la lista de palabras detectadas ("BLINK", "SHAKE", "NOD")."""
        found = []

        # Giroscopio sin su sesgo (la mediana de la ventana).
        gyro = window[:, CH_GYRO].astype(np.float64)
        gyro = gyro - np.median(gyro, axis=0)
        yaw = gyro[:, CH_GYRO_YAW - CH_GYRO.start]
        pitch = gyro[:, CH_GYRO_PITCH - CH_GYRO.start]
        recent_motion = float(np.abs(gyro[-self.blink_samples:]).max())

        # MECÁNICA 1: Parpadeo voluntario (Fz) -> BLINK
        frontal = window[-(self.blink_samples + BLINK_SMOOTH_SAMPLES - 1):, CH_FRONTAL]
        peak_to_peak = float(np.ptp(smoothed(frontal.astype(np.float64), BLINK_SMOOTH_SAMPLES)))
        if peak_to_peak > BLINK_THRESHOLD:
            if (self.blink_armed and recent_motion < BLINK_MOTION_GATE
                    and now - self.last_blink > BLINK_COOLDOWN_SEC):
                found.append(WORD_BLINK)
                self.last_blink = now
            self.blink_armed = False
        elif peak_to_peak < BLINK_THRESHOLD * BLINK_REARM_FRACTION:
            self.blink_armed = True

        # Movimientos de cabeza: negar = oscilación en YAW; asentir = en PITCH.
        # Si ambos ejes oscilan, gana el que tenga el pico más grande
        # (un movimiento nunca es perfectamente puro).
        rev_yaw = count_reversals(yaw, GYRO_THRESHOLD)
        rev_pitch = count_reversals(pitch, GYRO_THRESHOLD)
        yaw_peak = float(np.max(np.abs(yaw)))
        pitch_peak = float(np.max(np.abs(pitch)))
        shake_detected = rev_yaw >= SHAKE_MIN_REVERSALS and yaw_peak >= pitch_peak
        nod_detected = rev_pitch >= NOD_MIN_REVERSALS and pitch_peak > yaw_peak

        # MECÁNICA 2: Negación con la cabeza -> SHAKE. Una negación larga
        # sigue en la ventana varios bloques: solo cuenta una vez (si contara
        # dos, "andar" y "parar" se anularían).
        if shake_detected:
            if self.shake_armed and now - self.last_shake > HEAD_SHAKE_COOLDOWN_SEC:
                found.append(WORD_HEAD_SHAKE)
                self.last_shake = now
            self.shake_armed = False
        elif rev_yaw == 0:
            self.shake_armed = True

        # MECÁNICA 3: Asentir con la cabeza -> ataque, NOD, con cooldown de
        # ATTACK_COOLDOWN_SEC. Un asentimiento hecho durante el cooldown se
        # descarta (no queda "en cola"): hay que volver a asentir.
        attack_ready_in = max(0.0, ATTACK_COOLDOWN_SEC - (now - self.last_attack))
        if nod_detected:
            if self.nod_armed and attack_ready_in <= 0.0:
                found.append(WORD_ATTACK)
                self.last_attack = now
            self.nod_armed = False
        elif rev_pitch == 0:
            self.nod_armed = True

        self.debug = {
            "peak_to_peak": peak_to_peak, "motion": recent_motion,
            "gyro_peaks": np.abs(gyro).max(axis=0), "rev_yaw": rev_yaw,
            "rev_pitch": rev_pitch, "attack_ready_in": attack_ready_in,
        }
        return found


# -----------------------------------------------------------------------------
# SALIDA HACIA EL JUEGO: UDP (por defecto), teclado (--keys) o nada (--test)
# -----------------------------------------------------------------------------
class GameOutput:
    def __init__(self, mode="udp", host=GAME_HOST, port=GAME_PORT):
        self.mode = mode
        self.address = (host, port)
        self._sock = None
        self._kb = None
        if mode == "udp":
            self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        elif mode == "keys":
            if Controller is None:
                raise RuntimeError(
                    "No se pudo importar pynput. Instala la dependencia 'pynput' "
                    "para enviar pulsaciones de teclado."
                )
            self._kb = Controller()

    def _udp(self, text):
        try:
            self._sock.sendto(text.encode("utf-8"), self.address)
        except OSError as exc:
            # Red caída o IP inválida: avisa, pero no detiene la detección.
            print(f"[AVISO] No se pudo enviar {text!r} a {self.address}: {exc}", flush=True)

    def send(self, word, key):
        """Envía una señal: la palabra por UDP o la tecla con pynput."""
        if self._sock is not None:
            self._udp(word)
        elif self._kb is not None:
            self._kb.press(key)
            self._kb.release(key)

    def hello(self):
        """Dice al juego que el casco está conectado y qué señales envía."""
        if self._sock is not None:
            self._udp(f"HELLO {WORD_BLINK} {WORD_HEAD_SHAKE} {WORD_ATTACK}")

    def close(self):
        if self._sock is not None:
            self._sock.close()


# -----------------------------------------------------------------------------
# FUNCIONES DE MENSAJES EN TERMINAL
# -----------------------------------------------------------------------------
MESSAGES = {WORD_BLINK: "Parpadeo", WORD_HEAD_SHAKE: "Cabeza", WORD_ATTACK: "Muerde"}
KEYS = {WORD_BLINK: KEY_BLINK, WORD_HEAD_SHAKE: KEY_HEAD_SHAKE, WORD_ATTACK: KEY_ATTACK}


# -----------------------------------------------------------------------------
# CASCO
# -----------------------------------------------------------------------------
def connect():
    """Conecta con el primer Unicorn disponible, o lanza HeadsetError."""
    available_devices = UnicornPy.GetAvailableDevices(True)
    if len(available_devices) == 0:
        raise HeadsetError(
            "No se detectó ningún Unicorn Hybrid Black. Verifica que esté "
            "encendido y emparejado por Bluetooth, y que Unicorn Recorder esté cerrado.")
    errors = []
    for address in available_devices:
        try:
            device = UnicornPy.Unicorn(address)
            print(f"Conectado a Unicorn en {address}.", flush=True)
            return device
        except UnicornPy.DeviceException as exc:
            errors.append(f"  {address}: {exc}")
    raise HeadsetError(
        "Se detectaron dispositivos Unicorn, pero no fue posible conectarse:\n"
        + "\n".join(errors)
        + "\nComprueba que esté encendido y emparejado por Bluetooth, y cierra "
          "Unicorn Recorder u otras aplicaciones que puedan estar usándolo.")


def run_session(args, game):
    """Conecta, adquiere y detecta hasta Ctrl+C (KeyboardInterrupt) o hasta
    que el casco falle (UnicornPy.DeviceException / HeadsetError)."""
    device = connect()
    try:
        sampling_rate = UnicornPy.SamplingRate  # 250 Hz
        num_channels = device.GetNumberOfAcquiredChannels()
        if num_channels <= max(CH_GYRO_YAW, CH_GYRO_PITCH):
            raise HeadsetError(
                f"El dispositivo entrega {num_channels} canales y se necesita el "
                f"giroscopio (índices {CH_GYRO_YAW} y {CH_GYRO_PITCH}) para detectar "
                f"los movimientos de cabeza.")

        # Buffer de 1 segundo
        window_samples = int(sampling_rate)
        signal_buffer = np.zeros((window_samples, num_channels), dtype=np.float32)
        samples_received = 0
        detector = Detector(sampling_rate)

        frame_length = 25  # 100 ms por bloque
        receive_buffer_length = frame_length * num_channels * 4
        receive_buffer = bytearray(receive_buffer_length)

        device.StartAcquisition(False)
        print("Adquisición iniciada. Llenando buffer inicial (1 s)... Ctrl+C para salir.", flush=True)
        if not args.test and not args.keys:
            print("Abre el juego: su interfaz cerebral se activa sola y muestra 'Headset connected'.", flush=True)
        last_hello = -1e9
        last_debug_print = -1e9

        while True:
            if time.monotonic() - last_hello >= HELLO_INTERVAL_SEC:
                game.hello()
                last_hello = time.monotonic()

            device.GetData(frame_length, receive_buffer, receive_buffer_length)
            data_chunk = np.frombuffer(
                receive_buffer, dtype=np.float32,
                count=frame_length * num_channels
            ).reshape((frame_length, num_channels))

            # Ventana deslizante
            signal_buffer = np.roll(signal_buffer, -frame_length, axis=0)
            signal_buffer[-frame_length:, :] = data_chunk
            samples_received += frame_length

            # Esperar a que el buffer esté lleno para evitar falsas lecturas
            if samples_received < window_samples:
                continue

            now = time.monotonic()
            for word in detector.update(signal_buffer, now):
                game.send(word, KEYS[word])
                print(MESSAGES[word], flush=True)

            # DEPURACIÓN: valores medidos para ajustar umbrales
            if args.debug and now - last_debug_print >= DEBUG_PRINT_INTERVAL_SEC:
                d = detector.debug
                peaks = d["gyro_peaks"]
                print(f"[DEBUG] P2P(Fz)={d['peak_to_peak']:7.2f} (umbral {BLINK_THRESHOLD}) | "
                      f"Giro pico X/Y/Z={peaks[0]:5.0f}/{peaks[1]:5.0f}/{peaks[2]:5.0f} "
                      f"(umbral {GYRO_THRESHOLD}) | cambios negar={d['rev_yaw']} asentir={d['rev_pitch']} | "
                      f"ataque listo en {d['attack_ready_in']:3.1f} s", flush=True)
                last_debug_print = now

            time.sleep(0.01)
    finally:
        # Si el Bluetooth se cayó, parar también puede fallar: no importa.
        try:
            device.StopAcquisition()
        except Exception:
            pass
        del device


# -----------------------------------------------------------------------------
# PROGRAMA PRINCIPAL
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Unicorn Hybrid Black -> juego de Godot")
    parser.add_argument("--test", action="store_true",
                        help="Modo prueba: NO envía nada al juego, solo imprime mensajes.")
    parser.add_argument("--debug", action="store_true",
                        help="Imprime periódicamente los valores medidos para calibrar umbrales.")
    parser.add_argument("--keys", action="store_true",
                        help="Presiona teclas (B/N/Y) en vez de enviar UDP. El juego debe tener el foco.")
    parser.add_argument("--host", default=GAME_HOST,
                        help=f"IP del PC con el juego (por defecto {GAME_HOST}).")
    parser.add_argument("--port", type=int, default=GAME_PORT,
                        help=f"Puerto UDP del juego (por defecto {GAME_PORT}, ver Settings).")
    args = parser.parse_args()

    if UnicornPy is None:
        # También --test necesita el casco: sin UnicornPy no hay nada que leer.
        print(f"ERROR: No se pudo cargar UnicornPy: {UNICORNPY_ERROR}")
        if "License" in str(UNICORNPY_ERROR):
            print("Abre Unicorn Suite Hybrid Black -> Licenses -> Add License y vuelve a intentarlo.")
        elif UNICORNPY_FOLDER is None:
            print("No se encontró UnicornPy.pyd. Instala Unicorn Suite Hybrid Black (incluye")
            print("Unicorn Python), o define UNICORN_PY_PATH con la carpeta que contiene")
            print("UnicornPy.pyd, Unicorn.dll y Gtec.Licensing.Unicorn.dll.")
        else:
            print(f"UnicornPy está en {UNICORNPY_FOLDER} pero no se pudo cargar.")
        return 1

    if args.test:
        game = GameOutput("none")
        print("[MODO PRUEBA] Las señales NO se enviarán al juego.")
    elif args.keys:
        game = GameOutput("keys")
        print("Enviando teclas B (parpadeo), N (cabeza), Y (ataque). Deja el juego enfocado.")
    else:
        game = GameOutput("udp", args.host, args.port)
        print(f"Enviando BLINK / SHAKE / NOD por UDP a {args.host}:{args.port}.")

    try:
        while True:
            try:
                run_session(args, game)
            except (HeadsetError, UnicornPy.DeviceException) as exc:
                print(f"\nERROR del casco: {exc}", flush=True)
                print(f"Reintentando en {RECONNECT_DELAY_SEC:.0f} s... (Ctrl+C para salir)", flush=True)
                time.sleep(RECONNECT_DELAY_SEC)
    except KeyboardInterrupt:
        pass
    finally:
        game.close()
        print("\nDispositivo desconectado.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
