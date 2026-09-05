---
description: Google SRE Multi-Window Multi-Burn-Rate (MWMBR) alerting on OpenTelemetry metrics, eliminating alert storms and protecting error budgets.
metadata:
  tags: [slo, sli, burn-rate, mwmbr, prometheus-rules, alertmanager, sre]
---

# SLOs & Multi-Window Multi-Burn-Rate Alerting

Alerting on high CPU or raw error counts leads to alert fatigue and misses insidious slow-burn outages. The **Google SRE Multi-Window Multi-Burn-Rate (MWMBR)** model alerts on rate of **Error Budget Consumption**.

---

## 1. Multi-Window Multi-Burn-Rate Mathematical Framework

To prevent flapping and alert storms, MWMBR requires both a **long window** (to confirm sustained consumption) and a **short window** (to ensure the incident is actively occurring) to trigger:

| Alert Severity | Budget Consumed | Long Window ($W_L$) | Short Window ($W_S$) | Burn Rate Factor ($B$) | Target SLO |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Critical (Page)** | 2% | 1 hour | 5 minutes | **14.4x** | 99.9% |
| **Critical (Page)** | 5% | 6 hours | 30 minutes | **6.0x** | 99.9% |
| **Warning (Ticket)**| 10% | 24 hours (1d)| 2 hours | **3.0x** | 99.9% |
| **Warning (Ticket)**| 100% | 72 hours (3d)| 6 hours | **1.0x** | 99.9% |

For a 99.9% availability SLO ($SLO = 0.999$), the total error budget is $E = 1 - 0.999 = 0.001$ (0.1%).
- Burn rate threshold = $B 	imes E$
  - 14.4x rate = $14.4 	imes 0.001 = 0.0144$ (1.44% error rate).
  - 6.0x rate = $6.0 	imes 0.001 = 0.006$ (0.6% error rate).

---

## 2. Production Manifests
- Prometheus Recording & Alerting Rules: [`slo-mwmbr-rules.yaml`](../examples/alerting/slo-mwmbr-rules.yaml)
- Alertmanager Multi-Tier Routing: [`alertmanager.yaml`](../examples/alerting/alertmanager.yaml)
