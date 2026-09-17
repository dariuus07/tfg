# Detailed System Execution and Event Flow

## 1. Overview

This document specifies the technical lifecycle, synchronization barriers, and runtime event processing pipeline for the automated DevSecOps laboratory. The architecture eliminates race conditions during provisioning and guarantees deterministic threat detection, local AI triage, and incident dispatching.

---

## 2. Infrastructure Provisioning Phase (Terraform)

Terraform calculates a directed acyclic graph (DAG) based on explicit and implicit dependencies.

```text
       [ aws_vpc / Subnet / IGW / Route Tables / Security Groups ]
                                    │
                                    ▼
                      [ aws_instance.wazuh_manager ]
                                    │ (Exposes private IP)
                                    ▼
                       [ aws_instance.victim_host ]
                                    │ (Exposes private IP)
                                    ▼
                      [ aws_instance.attacker_host ]
```

1. **Network Baseline:** Allocates VPC CIDR `10.0.0.0/16`, creates public subnet `10.0.1.0/24`, attaches the Internet Gateway, and configures routing tables.
2. **Security Group Binding:** Restricts traffic while allowing internal subnet communication (`10.0.1.0/24`) for telemetry ports (TCP 1514, TCP 1515) and HTTP ingress (TCP 80).
3. **Manager Instantiation:** Provisions `wazuh_manager`. Its private IP is captured dynamically for downstream nodes.
4. **Victim Instantiation:** Binds `depends_on = [aws_instance.wazuh_manager]` and injects the manager's private IP into the victim's `user_data`.
5. **Attacker Instantiation:** Binds `depends_on = [aws_instance.victim_host]` and injects the target's private IP into the adversary `user_data`.

---

## 3. Host Bootstrap and Synchronization Phase (cloud-init)

To prevent payloads from striking the target before security controls are operational, provisioning uses active socket polling instead of static execution delays.

### Timeline Sequence

```text
Time (t)   Wazuh Manager             Victim Host (Target)        Adversary Host
   │
 t=0s      Bootstraps OS             Bootstraps OS               Bootstraps OS
   │       Installs Wazuh & Ollama   Installs Docker & Agent     Reads Target IP
   │       Pulls TinyLlama model     Configures ossec.conf       Enters polling loop:
   │       Opens TCP 1514/1515                                   GET Target:80 == 200?
   │                                                             (Refused / Connection fail)
   │                                 Enters synchronization      
   │                                 guard loop:                 
   │                                 ss -tan -> Manager:1514?    
   │                                                             
 t=60s     Manager Ready             Agent connects (ESTAB)      Polling continues...
   │                                 Guard released              (Waiting)
   │                                 Launches Docker container   (Waiting)
   │                                 Juice Shop binds port 80    (Waiting)
   │                                                             
 t=75s     Monitoring active         Port 80 responds HTTP 200   HTTP 200 detected
   │                                                             Pause: 10s stabilization
   │                                                             Executes Attack Suite:
   │                                                             - LFI / Path Traversal
   │                                                             - Reflected XSS
   │                                                             - SQL Injection
```

### Detailed Node Synchronization Logic

#### Node 1: Wazuh SIEM & Inference Engine
* **Execution:**
  1. Installs dependencies (`python3`, `requests`) and executes unattended Wazuh Manager installation.
  2. Installs Ollama, starts the system service, and downloads the `tinyllama` model via the local API.
  3. Writes `/var/ossec/integrations/custom-ai-telegram` and sets permissions to `750 root:wazuh`.
  4. Patches `/var/ossec/etc/ossec.conf` with the `<integration>` directive.
  5. Restarts `wazuh-manager` to activate daemon listeners on ports TCP 1514 and 1515.

#### Node 2: Target Workload Host
* **Execution:**
  1. Installs Docker Engine and the Wazuh Agent package.
  2. Injects the Manager private IP into `/var/ossec/etc/ossec.conf` and starts `wazuh-agent`.
  3. **Synchronization Barrier:** Executes an active check:
     ```bash
     until ss -tan | grep -q "${WAZUH_MANAGER_IP}:1514.*ESTAB"; do
         sleep 3
     done
     ```
  4. Once the session is confirmed, executes `docker run -d --name juice-shop -p 80:3000 bkimminich/juice-shop`.

#### Node 3: Threat Simulation Host
* **Execution:**
  1. Retrieves target private IP from Terraform context.
  2. **Health Check Loop:** Polls the application socket:
     ```bash
     until curl -s -o /dev/null -w "%{http_code}" http://$TARGET_IP:80 | grep -q "200"; do
         sleep 3
     done
     ```
  3. Applies a 10-second stabilization pause to allow SIEM ingestion buffers to settle.
  4. Dispatches the HTTP attack suite against the target.

---

## 4. Runtime Detection and AI Remediation Pipeline

When the adversary injects malicious payloads, the end-to-end incident handling pipeline executes automatically:

```text
[ Adversary Node ]
       │ HTTP Attacks (SQLi, XSS, Path Traversal)
       ▼
[ Victim Node: OWASP Juice Shop ]
       │ Access logs & container stderr/stdout
       ▼
[ Wazuh Agent (Victim) ]
       │ Encrypted log transmission (TCP 1514)
       ▼
[ Wazuh Manager: analysisd ]
       │ Decodes log -> Matches rule condition (Rule Level >= 7)
       ▼
[ Wazuh Manager: integratord ]
       │ Forks execution: /var/ossec/integrations/custom-ai-telegram <alert_json_path>
       ▼
[ Integration Script (custom-ai-telegram) ]
       │ 1. Parses JSON (Agent, Rule ID, Severity, Description, Source IP, Log)
       │ 2. Issues HTTP POST to [http://127.0.0.1:11434/api/generate](http://127.0.0.1:11434/api/generate)
       ▼
[ Local Ollama Instance (TinyLlama) ]
       │ Generates structured technical mitigation recommendations
       ▼
[ Integration Script ]
       │ Consolidates telemetry alert + AI mitigation payload
       │ Issues HTTP POST to [https://api.telegram.org/bot](https://api.telegram.org/bot)<TOKEN>/sendMessage
       ▼
[ SOC Analyst Telegram Client ]
```

---

## 5. Verification and Troubleshooting Procedures

### Bootstrap Validation
To review the execution logs of cloud-init on any node:
```bash
sudo tail -f /var/log/user-data.log
```

### Agent Connection Verification (Target Node)
Verify that the telemetry channel is established:
```bash
ss -tan | grep 1514
# Expected state: ESTAB
```

### SIEM Integration and Model Verification (Manager Node)
Verify that Ollama responds locally:
```bash
curl [http://127.0.0.1:11434/api/tags](http://127.0.0.1:11434/api/tags)
```

Inspect integration daemon activity and script execution logs:
```bash
sudo tail -f /var/ossec/logs/integrator.log
sudo tail -f /var/ossec/logs/ossec.log | grep -i "custom-ai-telegram"
```
