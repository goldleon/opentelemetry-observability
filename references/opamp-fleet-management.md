---
description: Architecture of the Open Agent Management Protocol (OpAMP), managing collector fleets, dynamic configuration, binary upgrades, and the OpAMP Supervisor.
metadata:
  tags: [opamp, fleet-management, supervisor, configuration, collector]
---

# OpAMP (Open Agent Management Protocol) & Fleet Operations

Managing hundreds or thousands of OpenTelemetry Collectors deployed across edge environments, Kubernetes clusters, and VMs manually via static files is operationally unscalable.

The **Open Agent Management Protocol (OpAMP)** is an open, vendor-neutral CNCF protocol specification that provides centralized control planes with real-time management over distributed collector fleets.

---

## 1. OpAMP Architecture: Client-Server Model

```
+-----------------------------------------------------------------------------+
| CENTRAL OBSERVABILITY CONTROL PLANE                                         |
|                                                                             |
|  +-----------------------------------------------------------------------+  |
|  | OpAMP Server                                                          |  |
|  | - Fleet Inventory & Agent Heartbeat Tracker                          |  |
|  | - Dynamic Configuration Manager (Canary, Blue/Green, Policy Rules)   |  |
|  | - Package Registry (Custom Collector Binaries & Checksums)           |  |
|  +-----------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------+
                                       ^
                                       | WebSocket (Full Duplex) or HTTP Long Poll
                                       | TLS 1.3 + Mutual TLS / Token Auth
                                       v
+-----------------------------------------------------------------------------+
| KUBERNETES NODE / VM                                                        |
|                                                                             |
|  +-----------------------------------------------------------------------+  |
|  | OPAMP SUPERVISOR (Standalone Watchdog Daemon: opampsupervisor)      |  |
|  |                                                                       |  |
|  |  - Implements OpAMP Client Protocol                                  |  |
|  |  - Spawns and supervises OpenTelemetry Collector Child Process        |  |
|  |  - Receives new configuration from OpAMP Server                      |  |
|  |  - Validates syntax and tests collector startup                       |  |
|  |  - Performs automatic rollback if child crashes                       |  |
|  |  - Downloads, verifies SHA256, and executes Collector binary upgrades |  |
|  +-----------------------------------------------------------------------+  |
|                                      |                                      |
|                                      | Spawns & Monitors via IPC / Signals  |
|                                      v                                      |
|  +-----------------------------------------------------------------------+  |
|  | OPENTELEMETRY COLLECTOR CHILD PROCESS                                 |  |
|  |                                                                       |  |
|  |  - Runs active ingestion pipelines (Receivers -> Processors -> Exp)   |  |
|  |  - Runs in-process opamp Extension for internal metrics reporting   |  |
|  +-----------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------+
```

---

## 2. In-Process OpAMP Extension vs. Out-of-Process OpAMP Supervisor

| Capability | In-Process OpAMP Extension | Out-of-Process OpAMP Supervisor |
| :--- | :--- | :--- |
| **Execution Context** | Runs inside the Collector process | Runs as a separate watchdog process |
| **Agent Health Reporting** | **Yes** (Heap, CPU, active pipelines) | **Yes** (Process alive, exit status) |
| **Report Effective Config**| **Yes** | **Yes** |
| **Dynamic Config Reload** | Limited (Collector restart often needed) | **Full Support** (Graceful restart/reload) |
| **Automatic Crash Rollback**| **No** (If config causes crash, process dies) | **Yes** (Catches crash, restores previous config) |
| **Binary / Version Upgrades**| **Impossible** (Cannot replace running binary)| **Full Support** (Downloads new binary, swaps) |

---

## 3. Remote Configuration & Safe Rollback Workflow

```mermaid
sequenceDiagram
    autonumber
    participant Server as OpAMP Server
    participant Sup as OpAMP Supervisor
    participant Col as Collector Process

    Server->>Sup: Push New Config: config_v2.yaml (SHA256: e3b0c44...)
    Sup->>Sup: Save config_v2.yaml to disk (.new)
    Sup->>Sup: Verify config syntax: otelcol validate --config=config_v2.yaml
    
    alt Config Validation Fails
        Sup->>Server: Report Status: FAILED (Syntax Error details)
        Sup->>Sup: Delete config_v2.yaml; retain config_v1.yaml
    else Config Validation Succeeds
        Sup->>Col: Send SIGTERM (or reload signal)
        Sup->>Sup: Spawn new Collector with config_v2.yaml
        
        alt Collector Crashes on Startup (OOM or Network Bind Fail)
            Sup->>Sup: Detect child exit (code != 0)
            Sup->>Sup: Roll back to config_v1.yaml
            Sup->>Col: Restart Collector with config_v1.yaml
            Sup->>Server: Report Status: ROLLBACK_TRIGGERED (Crash log attached)
        else Collector Starts & Passes Readiness Probe
            Sup->>Server: Report Status: RUNNING (Effective Config: config_v2.yaml)
        end
    end
```

---

## 4. Production OpAMP Supervisor Configuration

```yaml
# supervisor-config.yaml
server:
  endpoint: "wss://opamp-control-plane.monitoring.internal:443/v1/opamp"
  tls:
    insecure: false
    ca_file: "/etc/ssl/certs/opamp-ca.crt"
    cert_file: "/etc/ssl/certs/opamp-client.crt"
    key_file: "/etc/ssl/certs/opamp-client.key"
  headers:
    authorization: "Bearer secret-fleet-token"

agent:
  executable: "/usr/local/bin/otelcol-custom"
  description: "Enterprise Edge Node Collector"
  config_dir: "/etc/otelcol"
  config_file_name: "effective-config.yaml"

capabilities:
  reports_status: true
  accepts_remote_config: true
  reports_effective_config: true
  accepts_packages: true # Enables remote binary upgrades
```
