# Automated Cloud Threat Detection and AI-Assisted Incident Remediation

## Overview

This project implements an automated cloud security laboratory developed as a Capstone Project (TFG) for the Official Higher Vocational Degree in Computer Network Systems Administration (ASIR).

The environment is provisioned via Infrastructure as Code (Terraform) on Amazon Web Services (AWS) using a zero-touch approach (`terraform apply`). It deploys an end-to-end attack simulation, detection, telemetry ingestion, and AI-driven mitigation pipeline:

1. An automated adversary node simulates web application attacks against a vulnerable container.
2. A monitored target node hosts the application within Docker and collects telemetry via the Wazuh Agent.
3. A centralized Wazuh SIEM manager ingests logs and triggers high-severity rules.
4. A locally hosted Large Language Model (Ollama running TinyLlama) parses event data and generates actionable remediation guidance.
5. Technical incident alerts and mitigation instructions are dispatched to an administrator via the Telegram Bot API.

---

## Architecture

The infrastructure deploys within a dedicated AWS VPC across three isolated EC2 instances:

```text
[ Adversary Node ] ──( Exploitation Traffic )──► [ Monitored Target (Juice Shop) ]
                                                            │
                                                 (Encrypted Telemetry :1514)
                                                            │
                                                            ▼
                                                 [ Wazuh SIEM + Local Ollama ]
                                                            │
                                                 (Inference: Mitigations)
                                                            │
                                                            ▼
                                                 [ Telegram Bot API ]
```

### Components

* **Control & Remediation Tier (`wazuh-siem-manager`):**
  * **SIEM Engine:** Wazuh Manager handles log decoding, signature matching, and alerting.
  * **Local Inference:** Ollama serves an offline, quantized LLM (TinyLlama) locally to prevent exfiltration of sensitive telemetry to third-party APIs.
  * **Integration Script:** A custom Python daemon bridge (`wazuh-integratord`) extracts JSON alert payloads, generates prompts for the Ollama REST API, and formats the output for Telegram.
* **Monitored Workload Tier (`victim-juice-shop`):**
  * **Container Runtime:** Docker Engine executing the OWASP Juice Shop vulnerable web application.
  * **Host Security Agent:** Wazuh Agent configured for host auditing, container visibility, and system log aggregation.
  * **Synchronization Guard:** Application startup is delayed until an active TCP connection to port 1514 on the SIEM manager is established.
* **Adversary Emulation Tier (`adversary-traffic-generator`):**
  * **Availability Polling:** Actively polls the target web server (`HTTP 200`) before launching exploits to avoid false positives.
  * **Automated Payloads:** Executes Local File Inclusion (LFI), Reflected Cross-Site Scripting (XSS), and SQL Injection (SQLi) attack patterns.

---

## Repository Structure

```text
.
├── terraform/
│   ├── main.tf                     # Provider and global configuration
│   ├── network.tf                  # VPC, subnets, IGW, and route tables
│   ├── security_groups.tf          # Traffic isolation and firewall rules
│   ├── instances.tf                # EC2 resources and user_data bindings
│   ├── variables.tf                # Input variable definitions
│   ├── outputs.tf                  # IP addresses and status outputs
│   ├── terraform.tfvars.example    # Configuration values template
│   └── scripts/
│       ├── wazuh_manager_bootstrap.sh  # SIEM & Ollama runtime bootstrap
│       ├── victim_bootstrap.sh         # Docker, agent setup & synchronization
│       ├── attacker_bootstrap.sh       # Target verification & attack execution
│       └── custom-ai-telegram.py       # Integration hook (SIEM -> Ollama -> Telegram)
└── docs/
    └── architecture.png
```

---

## Deployment Workflow

### Prerequisites
* Terraform >= 1.5.0 installed.
* Configured AWS CLI profile with administrative access to VPC and EC2.
* A Telegram Bot Token generated via `@BotFather` and the recipient `chat_id`.
* An existing SSH Key Pair registered in your designated AWS deployment region.

### Step 1: Configuration
Clone the repository and prepare the configuration variables:

```bash
git clone https://github.com/dariuus07/tfg.git
cd tfg/terraform
cp terraform.tfvars.example terraform.tfvars
```

Populate `terraform.tfvars` with your parameters:

```hcl
aws_region       = "eu-west-1"
ssh_key_name     = "your-key-name"
telegram_token   = "0000000000:AAExampleTokenString"
telegram_chat_id = "123456789"
```

### Step 2: Infrastructure Provisioning
Run the execution plan to deploy the environment:

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

### Step 3: Operational Verification
1. **Host Bootstrapping:** Terraform provisions resources and injects initialization scripts into EC2 `user_data`.
2. **Telemetry Synchronization:** The target host loops until the Wazuh Agent socket to `manager:1514` enters the `ESTABLISHED` state before binding port 80 for the application container.
3. **Attack Dispatch:** The adversary node waits for the HTTP 200 state on the victim IP and executes the attack suite.
4. **Alert Delivery:** Wazuh triggers Level 7+ alert rules, queries the local TinyLlama model for remediation tactics, and sends the notification to Telegram.

---

## Environment Teardown

To avoid ongoing AWS compute and networking charges, terminate all infrastructure when testing is finished:

```bash
terraform destroy -auto-approve
```

---

## Technical Considerations

* **Compute Sizing:** The SIEM node requires a `t3.xlarge` instance (4 vCPUs, 16 GB RAM) minimum to run the Wazuh Indexer/Dashboard alongside the Ollama inference engine.
* **Race Condition Avoidance:** Synchronization between hosts is driven by network socket polling rather than static execution delays (`sleep`), preventing race conditions during provisioning.
