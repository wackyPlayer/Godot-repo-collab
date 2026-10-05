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

Por defecto envía la palabra por UDP al puerto del juego (no hace falta que la
ventana del juego tenga el foco). Cada segundo envía además "HELLO BLINK SHAKE
NOD": el juego activa solo su interfaz cerebral al recibirlo y muestra
"Headset connected". Las acciones se cambian en Settings > Brain interface.

Lo más fácil: doble clic en tools/unicorn_start.bat (instala numpy si falta).
UnicornPy se busca solo en la instalación de Unicorn Suite
(Documentos\\gtec\\Unicorn Suite\\...) y junto a este script; o define la
variable UNICORN_PY_PATH con la carpeta que contiene UnicornPy.pyd.

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


def add_unicorn_paths():
    """Añade a sys.path la carpeta con UnicornPy.pyd, para no tener que
    configurar PYTHONPATH: UNICORN_PY_PATH, junto a este script, o la
    instalación de Unicorn Suite en Documentos."""
    here = Path(__file__).resolve().parent
    candidates = [here, here / "Lib"]
    if os.environ.get("UNICORN_PY_PATH"):
        candidates.insert(0, Path(os.environ["UNICORN_PY_PATH"]))
    home = Path.home()
    for docs in (home / "Documents", home / "Documentos",
                 home / "OneDrive" / "Documents", home / "OneDrive" / "Documentos"):
        suite = docs / "gtec" / "Unicorn Suite"
        if suite.is_dir():
            candidates += sorted(p.parent for p in suite.rglob("UnicornPy.pyd"))
    for folder in candidates:
        if (folder / "UnicornPy.pyd").is_file():
            sys.path.append(str(folder))
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

BLINK_THRESHOLD = 120.0    # Pico a pico en Fz
BLINK_COOLDOWN_SEC = 0.5

# Movimientos de cabeza: oscilación del giroscopio (grados/s)
GYRO_THRESHOLD = 80.0          # Cada vaivén debe superar este valor (en ambos sentidos)
SHAKE_MIN_REVERSALS = 2        # Negar: cambios de sentido necesarios (izq-der-izq = 2)
NOD_MIN_REVERSALS = 2          # Asentir: cambios de sentido necesarios (arriba-abajo-arriba = 2)
HEAD_SHAKE_COOLDOWN_SEC = 1.2  # Debe ser > 1 s (tamaño de la ventana)
ATTACK_COOLDOWN_SEC = 2.0      # Tiempo mínimo entre ataques

# Intervalo para imprimir valores en modo --debug
DEBUG_PRINT_INTERVAL_SEC = 0.5

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

    def send(self, word, key):
        """Envía una señal: la palabra por UDP o la tecla con pynput."""
        if self._sock is not None:
            self._sock.sendto(word.encode("utf-8"), self.address)
        elif self._kb is not None:
            self._kb.press(key)
            self._kb.release(key)

    def hello(self):
        """Dice al juego que el casco está conectado y qué señales envía."""
        if self._sock is not None:
            text = f"HELLO {WORD_BLINK} {WORD_HEAD_SHAKE} {WORD_ATTACK}"
            self._sock.sendto(text.encode("utf-8"), self.address)

    def close(self):
        if self._sock is not None:
            self._sock.close()


# -----------------------------------------------------------------------------
# FUNCIONES DE MENSAJES EN TERMINAL
# -----------------------------------------------------------------------------
def msg_cabeza():
    """Se imprime cada vez que se detecta una negación con la cabeza (SHAKE)."""
    print("Cabeza", flush=True)


def msg_parpadeo():
    """Se imprime cada vez que se detecta un parpadeo (BLINK)."""
    print("Parpadeo", flush=True)


def msg_muerde():
    """Se imprime cada vez que se detecta un asentimiento (NOD, ataque)."""
    print("Muerde", flush=True)


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

    if UnicornPy is None and not args.test:
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

    if UnicornPy is None and args.test:
        print("[MODO PRUEBA] UnicornPy no está disponible; se ejecuta sin conectar al dispositivo.")
        return 0

    if args.test:
        game = GameOutput("none")
        print("[MODO PRUEBA] Las señales NO se enviarán al juego.")
    elif args.keys:
        game = GameOutput("keys")
        print("Enviando teclas B (parpadeo), N (cabeza), Y (ataque). Deja el juego enfocado.")
    else:
        game = GameOutput("udp", args.host, args.port)
        print(f"Enviando BLINK / SHAKE / NOD por UDP a {args.host}:{args.port}.")

    # 1. Conexión al dispositivo
    available_devices = UnicornPy.GetAvailableDevices(True)
    if len(available_devices) == 0:
        print(
            "ERROR: No se detectó ningún Unicorn Hybrid Black. Verifica que esté "
            "encendido y emparejado por Bluetooth, y que Unicorn Recorder esté cerrado."
        )
        return 1

    device = None
    device_address = None
    connection_errors = []
    for candidate_address in available_devices:
        try:
            device = UnicornPy.Unicorn(candidate_address)
            device_address = candidate_address
            break
        except UnicornPy.DeviceException as exc:
            connection_errors.append((candidate_address, exc))

    if device is None:
        print("ERROR: Se detectaron dispositivos Unicorn, pero no fue posible conectarse.")
        for address, error in connection_errors:
            print(f"  {address}: {error}")
        print(
            "Comprueba que el dispositivo esté encendido y emparejado por Bluetooth, "
            "y cierra Unicorn Recorder u otras aplicaciones que puedan estar usándolo."
        )
        return 1

    print(f"Conectado a Unicorn en {device_address}.")

    sampling_rate = UnicornPy.SamplingRate  # 250 Hz
    num_channels = device.GetNumberOfAcquiredChannels()

    if num_channels <= max(CH_GYRO_YAW, CH_GYRO_PITCH):
        print(f"ERROR: El dispositivo entrega {num_channels} canales y se necesita el "
              f"giroscopio (índices {CH_GYRO_YAW} y {CH_GYRO_PITCH}) para detectar "
              f"los movimientos de cabeza.")
        del device
        return 1

    # Buffer de 1 segundo
    window_samples = int(sampling_rate)
    signal_buffer = np.zeros((window_samples, num_channels), dtype=np.float32)
    samples_received = 0

    # Estados
    last_blink_time = 0.0
    last_shake_time = 0.0
    last_attack_time = -1e9      # Permite el primer ataque de inmediato
    nod_armed = True             # Se rearma cuando la ventana queda sin cabeceos
    last_debug_print = 0.0

    frame_length = 25  # 100 ms por bloque
    receive_buffer_length = frame_length * num_channels * 4
    receive_buffer = bytearray(receive_buffer_length)

    device.StartAcquisition(False)
    print("Adquisición iniciada. Llenando buffer inicial (1 s)... Ctrl+C para salir.")
    if not args.test and not args.keys:
        print("Abre el juego: su interfaz cerebral se activa sola y muestra 'Headset connected'.")
    last_hello = 0.0

    try:
        while True:
            if time.time() - last_hello >= HELLO_INTERVAL_SEC:
                game.hello()
                last_hello = time.time()

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

            current_time = time.time()

            # -------------------------------------------------------------
            # MECÁNICA 1: Parpadeo voluntario (Fz) -> BLINK
            # (detección tomada de Neuro_a_tecla_funciona_mandibula.py)
            # -------------------------------------------------------------
            frontal_signal = signal_buffer[:, CH_FRONTAL]
            peak_to_peak = np.ptp(frontal_signal[-frame_length:])

            if peak_to_peak > BLINK_THRESHOLD and (current_time - last_blink_time) > BLINK_COOLDOWN_SEC:
                game.send(WORD_BLINK, KEY_BLINK)
                msg_parpadeo()
                last_blink_time = current_time

            # -------------------------------------------------------------
            # Movimientos de cabeza (giroscopio)
            # Negar = oscilación en el eje YAW; asentir = oscilación en PITCH.
            # Si ambos ejes oscilan, gana el que tenga el pico más grande
            # (un movimiento nunca es perfectamente puro).
            # -------------------------------------------------------------
            yaw = signal_buffer[:, CH_GYRO_YAW].astype(np.float64)
            yaw = yaw - np.median(yaw)          # quita el sesgo del sensor
            pitch = signal_buffer[:, CH_GYRO_PITCH].astype(np.float64)
            pitch = pitch - np.median(pitch)

            rev_yaw = count_reversals(yaw, GYRO_THRESHOLD)
            rev_pitch = count_reversals(pitch, GYRO_THRESHOLD)
            yaw_peak = float(np.max(np.abs(yaw)))
            pitch_peak = float(np.max(np.abs(pitch)))

            shake_detected = rev_yaw >= SHAKE_MIN_REVERSALS and yaw_peak >= pitch_peak
            nod_detected = rev_pitch >= NOD_MIN_REVERSALS and pitch_peak > yaw_peak

            # -------------------------------------------------------------
            # MECÁNICA 2: Negación con la cabeza -> SHAKE
            # -------------------------------------------------------------
            if shake_detected and (current_time - last_shake_time) > HEAD_SHAKE_COOLDOWN_SEC:
                game.send(WORD_HEAD_SHAKE, KEY_HEAD_SHAKE)
                msg_cabeza()
                last_shake_time = current_time

            # -------------------------------------------------------------
            # MECÁNICA 3: Asentir con la cabeza -> ataque, NOD
            # con cooldown de ATTACK_COOLDOWN_SEC. Un asentimiento hecho durante
            # el cooldown se descarta (no queda "en cola" para dispararse
            # cuando termine): hay que volver a asentir.
            # -------------------------------------------------------------
            attack_ready_in = max(0.0, ATTACK_COOLDOWN_SEC - (current_time - last_attack_time))

            if nod_detected:
                if nod_armed and attack_ready_in <= 0.0:
                    game.send(WORD_ATTACK, KEY_ATTACK)
                    msg_muerde()
                    last_attack_time = current_time
                nod_armed = False
            elif rev_pitch == 0:
                nod_armed = True

            # -------------------------------------------------------------
            # DEPURACIÓN: valores medidos para ajustar umbrales
            # -------------------------------------------------------------
            if args.debug and (current_time - last_debug_print) >= DEBUG_PRINT_INTERVAL_SEC:
                gyro_peaks = np.abs(
                    signal_buffer[:, 11:14] - np.median(signal_buffer[:, 11:14], axis=0)
                ).max(axis=0)
                print(f"[DEBUG] P2P(Fz)={peak_to_peak:7.2f} (umbral {BLINK_THRESHOLD}) | "
                      f"Giro pico X/Y/Z={gyro_peaks[0]:5.0f}/{gyro_peaks[1]:5.0f}/{gyro_peaks[2]:5.0f} "
                      f"(umbral {GYRO_THRESHOLD}) | cambios negar={rev_yaw} asentir={rev_pitch} | "
                      f"ataque listo en {attack_ready_in:3.1f} s", flush=True)
                last_debug_print = current_time

            time.sleep(0.01)

    except KeyboardInterrupt:
        pass
    finally:
        device.StopAcquisition()
        del device
        game.close()
        print("\nDispositivo desconectado.")


if __name__ == "__main__":
    raise SystemExit(main())