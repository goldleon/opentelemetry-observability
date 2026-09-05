---
description: Deep dive into OpenTelemetry Semantic Conventions, standardized namespaces, Schema URLs, and GenAI / LLM telemetry standards.
metadata:
  tags: [semconv, semantic-conventions, schema-url, genai, llm, http, database]
---

# Semantic Conventions & Telemetry Schemas

Semantic Conventions (SemConv) define standardized attribute keys, metric names, and event structures across programming languages and observability backends. Adhering to SemConv prevents namespace collisions, enables out-of-the-box vendor dashboards, and guarantees interoperability.

---

## 1. Core Namespace Taxonomy

```
+--------------------------------------------------------------------------+
| SEMANTIC CONVENTION NAMESPACES                                           |
+-------------------+------------------------------------------------------+
| Namespace         | Target Entity / Operation                            |
+-------------------+------------------------------------------------------+
| http.*            | HTTP client/server requests, responses, routes       |
| db.*              | Database client queries, connections, procedures     |
| rpc.*             | gRPC, Apache Thrift, Connect RPC calls               |
| messaging.*       | Kafka, RabbitMQ, SQS, pub/sub queues and batches     |
| faas.*            | Function-as-a-Service (AWS Lambda, Google Cloud Run) |
| k8s.*             | Kubernetes cluster, pod, container, node attributes  |
| host.*            | Physical/virtual server CPU, memory, OS metadata     |
| cloud.*           | Cloud provider regions, zones, accounts (AWS, GCP)   |
| gen_ai.*          | Large Language Models, embeddings, agent workflows   |
+-------------------+------------------------------------------------------+
```

---

## 2. HTTP Semantic Conventions (v1.26+ Modern vs. Legacy)

The OpenTelemetry project migrated HTTP conventions from legacy syntax to clean, unambiguous namespaces.

| Attribute Purpose | Legacy Syntax (Deprecated) | Modern Stable Syntax (v1.26+) | Example Value |
| :--- | :--- | :--- | :--- |
| **HTTP Request Method** | `http.method` | `http.request.method` | `"POST"`, `"GET"` |
| **HTTP Response Status**| `http.status_code` | `http.response.status_code`| `200`, `404`, `500` |
| **HTTP Route / Pattern**| `http.route` | `http.route` | `"/users/{id}/orders"` |
| **Target URL / Path** | `http.target` | `url.path` | `"/users/42/orders"` |
| **Query String** | `http.url` | `url.query` | `"sort=desc&limit=10"` |
| **Full URL** | `http.url` | `url.full` | `"https://api.acme.com/v1"` |
| **Client IP** | `http.client_ip` | `client.address` | `"192.168.1.50"` |
| **Server Hostname** | `net.host.name` | `server.address` | `"api.acme.com"` |
| **Server Port** | `net.host.port` | `server.port` | `443` |

---

## 3. Database Semantic Conventions

Database client spans capture remote query latency without leaking sensitive PII query parameters.

- **`db.system`** (Required): Identifies the DBMS: `"postgresql"`, `"mysql"`, `"redis"`, `"mongodb"`, `"clickhouse"`.
- **`db.operation`**: Operation verb: `"SELECT"`, `"INSERT"`, `"UPDATE"`, `"SET"`.
- **`db.collection.name`**: Target table or collection: `"users"`, `"order_items"`.
- **`db.query.text`**: Sanitized query string with literal parameters parameterized:
  ```sql
  -- Sanitized:
  SELECT * FROM users WHERE user_id = ? AND status = ?
  ```
- **`server.address`**: Database host (e.g., `"db-primary.internal"`).
- **`server.port`**: Database port (e.g., `5432`).

---

## 4. GenAI / LLM Semantic Conventions (`gen_ai.*`)

As generative AI and agentic systems became mainstream, OpenTelemetry introduced dedicated semantic conventions for LLM operations, chat completions, vector embeddings, and agent tool execution.

### 4.1 Key Attributes

| Attribute Key | Type | Description | Example |
| :--- | :--- | :--- | :--- |
| **`gen_ai.system`** | String | Provider or model family | `"openai"`, `"anthropic"`, `"gemini"`, `"ollama"` |
| **`gen_ai.request.model`** | String | Requested model identifier | `"gpt-4o"`, `"gemini-1.5-pro"`, `"claude-3-5-sonnet"` |
| **`gen_ai.response.model`** | String | Actual model servicing the request | `"gpt-4o-2024-08-06"` |
| **`gen_ai.request.temperature`**| Double | Model temperature parameter | `0.7` |
| **`gen_ai.request.max_tokens`** | Int | Configured completion token ceiling | `4096` |
| **`gen_ai.usage.input_tokens`** | Int | Prompt / context token count | `1240` |
| **`gen_ai.usage.output_tokens`**| Int | Generated completion token count | `312` |
| **`gen_ai.response.finish_reasons`**| Array[String] | Reason generation stopped | `["stop"]`, `["length"]`, `["tool_calls"]` |

### 4.2 Standard GenAI Metrics
- **`gen_ai.client.token.usage`** (Histogram): Token counts per request, segmented by `gen_ai.token.type: "input" | "output"`.
- **`gen_ai.client.operation.duration`** (Histogram): Request latency from invocation to final token completion.
- **`gen_ai.server.time_to_first_token`** (Histogram): Latency to the initial streaming token (TTFT).

---

## 5. Schema URLs & Version Translation

As semantic conventions evolve, attribute keys change. The **Schema URL** mechanism prevents breaking downstream dashboards when microservices upgrade SDK versions at different times.

### 5.1 How Schema Translation Works
Every Resource and Scope emitted by an SDK declares its Schema URL:
```json
{
  "schema_url": "https://opentelemetry.io/schemas/1.26.0",
  "resource": {
    "attributes": [
      { "key": "service.name", "value": { "stringValue": "payment-api" } }
    ]
  }
}
```
If an older collector receives telemetry with an older schema (e.g., `1.20.0`), or if an ingestion pipeline requires forward compatibility:
1. The OpenTelemetry Collector uses the **Schema Translation Engine**.
2. It loads the official OpenTelemetry Schema files (`.yaml` migration maps).
3. The collector automatically renames attributes (e.g., translating `http.method` $\to$ `http.request.method`) dynamically without dropping data.
