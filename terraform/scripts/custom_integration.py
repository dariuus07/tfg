#!/usr/bin/env python3
# custom_integration.py
# Integracion personalizada de Wazuh (SIEM -> Ollama -> Telegram).
# Wazuh (el demonio integratord) ejecuta este script cuando se dispara una
# regla del nivel configurado y le pasa en sys.argv[1] la RUTA del fichero JSON
# que contiene la alerta. El flujo es: leer alerta -> extraer campos -> pedir
# una mitigacion a la IA local (Ollama/TinyLlama) -> notificar por Telegram.

import datetime
import json
import sys

import requests

# Fichero de configuracion (credenciales y endpoints) escrito por el bootstrap
# con permisos restrictivos (0640 root:wazuh). Mantiene los secretos fuera de
# este script y fuera de ossec.conf.
CONFIG_PATH = "/var/ossec/integrations/custom-ai-telegram.conf"

# Log propio de la integracion, dentro del arbol de logs de Wazuh.
LOG_PATH = "/var/ossec/logs/integrations.log"

# Timeouts explicitos: la inferencia local puede tardar; Telegram es rapido.
OLLAMA_TIMEOUT = 60
TELEGRAM_TIMEOUT = 15


def log(message):
    # Escribe una linea con marca de tiempo UTC en el log de la integracion y,
    # como respaldo, en stderr (que Wazuh recoge en ossec.log). Nunca lanza.
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = f"[custom-ai-telegram] {timestamp} {message}"
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError:
        pass
    print(line, file=sys.stderr, flush=True)


def load_config():
    # Carga y valida la configuracion. Aborta si falta el fichero, no es JSON
    # valido o carece de algun parametro obligatorio.
    try:
        with open(CONFIG_PATH, encoding="utf-8") as handle:
            config = json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        log(f"ERROR: no se pudo cargar la configuracion: {exc}")
        sys.exit(1)

    for key in ("telegram_token", "telegram_chat_id", "ollama_url", "ollama_model"):
        if not config.get(key):
            log(f"ERROR: falta el parametro de configuracion '{key}'")
            sys.exit(1)
    return config


def read_alert(path):
    # Lee y parsea el fichero JSON de la alerta que inyecta Wazuh en argv[1].
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        log(f"ERROR: no se pudo leer la alerta '{path}': {exc}")
        sys.exit(1)


def extract_fields(alert):
    # Extrae de forma defensiva (con valores por defecto) los campos relevantes
    # de la estructura de la alerta de Wazuh.
    rule = alert.get("rule", {})
    agent = alert.get("agent", {})
    data = alert.get("data", {})
    full_log = alert.get("full_log") or ""
    return {
        "rule_id": rule.get("id", "N/D"),
        "level": rule.get("level", "N/D"),
        "description": rule.get("description", "N/D"),
        "agent_name": agent.get("name", "N/D"),
        "src_ip": data.get("srcip") or alert.get("srcip") or "N/D",
        "full_log": full_log[:500],
    }


def query_ollama(config, fields):
    # Construye el prompt con los datos de la alerta y solicita una mitigacion
    # a la API local de Ollama. Cualquier fallo devuelve un texto de respaldo
    # para que la notificacion se envie igualmente.
    prompt = (
        "Actua como analista SOC. Ante la siguiente alerta de seguridad, propon "
        "una mitigacion tecnica breve y accionable en espanol.\n"
        f"Regla: {fields['description']} (ID {fields['rule_id']}, nivel {fields['level']}).\n"
        f"IP origen: {fields['src_ip']}.\n"
        f"Log: {fields['full_log']}"
    )
    payload = {"model": config["ollama_model"], "prompt": prompt, "stream": False}
    try:
        response = requests.post(config["ollama_url"], json=payload, timeout=OLLAMA_TIMEOUT)
        response.raise_for_status()
        body = response.json()
    except requests.exceptions.RequestException as exc:
        log(f"ERROR: fallo la consulta a Ollama: {exc}")
        return "No se pudo generar la mitigacion (Ollama no disponible)."
    except json.JSONDecodeError as exc:
        log(f"ERROR: respuesta de Ollama no es JSON valido: {exc}")
        return "No se pudo generar la mitigacion (respuesta invalida de Ollama)."
    return body.get("response", "").strip() or "Ollama no devolvio contenido."


def build_message(fields, mitigation):
    # Compone el texto plano que se enviara por Telegram.
    return (
        "Alerta de seguridad (Wazuh)\n"
        f"Regla: {fields['description']}\n"
        f"ID / Nivel: {fields['rule_id']} / {fields['level']}\n"
        f"Agente: {fields['agent_name']}\n"
        f"IP origen: {fields['src_ip']}\n\n"
        f"Mitigacion sugerida (IA):\n{mitigation}"
    )


def send_telegram(config, message):
    # Envia el mensaje mediante la API de bots de Telegram. Devuelve True/False.
    url = f"https://api.telegram.org/bot{config['telegram_token']}/sendMessage"
    payload = {"chat_id": config["telegram_chat_id"], "text": message}
    try:
        response = requests.post(url, json=payload, timeout=TELEGRAM_TIMEOUT)
        response.raise_for_status()
    except requests.exceptions.RequestException as exc:
        log(f"ERROR: fallo el envio a Telegram: {exc}")
        return False
    return True


def main():
    # argv[1] es la ruta del fichero de alerta que inyecta Wazuh.
    if len(sys.argv) < 2:
        log("ERROR: no se recibio la ruta del fichero de alerta (argv[1])")
        sys.exit(1)

    config = load_config()
    alert = read_alert(sys.argv[1])
    fields = extract_fields(alert)
    log(f"procesando alerta regla={fields['rule_id']} nivel={fields['level']} src={fields['src_ip']}")

    mitigation = query_ollama(config, fields)
    message = build_message(fields, mitigation)

    if send_telegram(config, message):
        log("notificacion enviada a Telegram")
    else:
        log("no se pudo enviar la notificacion a Telegram")
        sys.exit(1)


if __name__ == "__main__":
    main()
