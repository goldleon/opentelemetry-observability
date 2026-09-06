# OpenTelemetry Transformation Language (OTTL) Specification & Production Cookbook

OTTL (OpenTelemetry Transformation Language) provides a domain-specific, declarative grammar for querying, mutating, filtering, and enriching telemetry payloads directly within OpenTelemetry Collector processors (`transformprocessor`, `filterprocessor`, `routingprocessor`).

---

## 1. OTTL Contexts & Path Expressions

OTTL expressions execute within a specific telemetry evaluation context. The context dictates which fields and sub-objects are accessible:

| Context | Target Signal | Root Identifier | Common Paths |
| :--- | :--- | :--- | :--- |
| `resource` | All signals | `resource` | `resource.attributes["service.name"]`, `resource.schema_url` |
| `scope` | All signals | `scope` | `scope.name`, `scope.version`, `scope.attributes` |
| `trace` | Traces | `trace` | `trace.trace_state` |
| `span` | Traces | `span` | `span.name`, `span.kind`, `span.status.code`, `span.attributes["http.status_code"]`, `span.start_time_unix_nano` |
| `spanevent` | Traces | `spanevent` | `spanevent.name`, `spanevent.timestamp_unix_nano`, `spanevent.attributes` |
| `metric` | Metrics | `metric` | `metric.name`, `metric.description`, `metric.unit`, `metric.type` |
| `datapoint` | Metrics | `datapoint` | `datapoint.value_double`, `datapoint.value_int`, `datapoint.attributes["host"]`, `datapoint.exemplars` |
| `log` | Logs | `log` | `log.body`, `log.severity_number`, `log.severity_text`, `log.attributes["user.id"]` |

### Path Syntax Rules
- **Map access**: `attributes["key.name"]` or `resource.attributes["k8s.pod.name"]`.
- **Nested maps**: `attributes["json"]["nested_field"]`.
- **Indexing arrays**: `attributes["tags"][0]`.
- **Literal types**: Strings (`"value"`), Integers (`42`), Floats (`3.14`), Booleans (`true`/`false`), Nil (`nil`).

---

## 2. OTTL Function Reference

### String Manipulation
- `set(target, value)`: Sets target path to value.
- `Concat([str1, str2, ...], delimiter)`: Concatenates strings with delimiter.
- `Split(str, delimiter)`: Splits a string into an array.
- `Substring(str, start, length)`: Extracts substring.
- `replace_pattern(target, regex, replacement)`: Replaces first regex match.
- `replace_all_patterns(target, regex, replacement)`: Replaces all regex matches (essential for PII masking).
- `truncate_all(target, max_length)`: Truncates all strings in target map to length.
- `delete_key(map, key)`: Deletes key from map.
- `delete_matching_keys(map, regex)`: Deletes keys matching regex pattern.

### Type Conversion & Parsing
- `ParseJSON(str)`: Parses JSON string into structured map.
- `ConvertCase(str, "lower" | "upper" | "snake" | "camel")`: Converts string casing.
- `IsMatch(target, regex)`: Boolean check if target matches regex.
- `merge_maps(target_map, source_map, "insert" | "update" | "upsert")`: Merges two maps.

### Error Handling & Modes
- `error_mode: ignore`: Skips failed statements silently and continues executing subsequent statements.
- `error_mode: silent`: Logs nothing on evaluation failure; drops failing item if in filter.
- `error_mode: propagate`: Halts processor and surfaces error (use in dev/testing).

---

## 3. Production OTTL Cookbook

### Recipe 1: PII Masking (Credit Cards, Social Security, Emails)
```yaml
processors:
  transform/pii_masking:
    error_mode: ignore
    log_statements:
      - context: log
        statements:
          # Mask Email Addresses
          - replace_all_patterns(log.body, "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}", "[REDACTED_EMAIL]")
          # Mask 16-digit Credit Card Numbers
          - replace_all_patterns(log.body, "\b(?:\d[ -]*?){13,16}\b", "[REDACTED_CC]")
          # Mask Social Security Numbers
          - replace_all_patterns(log.body, "\b\d{3}-\d{2}-\d{4}\b", "[REDACTED_SSN]")
          # Redact sensitive attributes
          - delete_matching_keys(log.attributes, "(?i)(password|secret|token|authorization|api_key)")
```

### Recipe 2: HTTP Route Normalization & High-Cardinality Fix
```yaml
processors:
  transform/http_normalization:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          # If span name contains UUIDs or numbers, normalize to route pattern
          - set(span.name, Concat([span.attributes["http.method"], " ", span.attributes["http.route"]], "")) where span.attributes["http.route"] != nil
          # Fix HTTP status code mapping to OpenTelemetry span status
          - set(span.status.code, 2) where span.attributes["http.status_code"] >= 500
          - set(span.status.description, "Internal Server Error") where span.attributes["http.status_code"] >= 500
```

### Recipe 3: W3C Baggage Extraction to Span Attributes
```yaml
processors:
  transform/baggage_extraction:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          # Extract tenant_id and user_tier propagated through baggage
          - set(span.attributes["app.tenant_id"], span.attributes["baggage.tenant_id"]) where span.attributes["baggage.tenant_id"] != nil
          - set(span.attributes["app.user_tier"], span.attributes["baggage.user_tier"]) where span.attributes["baggage.user_tier"] != nil
```

### Recipe 4: Structured Log Parsing from Raw Body
```yaml
processors:
  transform/log_parsing:
    error_mode: ignore
    log_statements:
      - context: log
        statements:
          # Parse JSON payload into structured attributes
          - merge_maps(log.attributes, ParseJSON(log.body), "upsert") where IsMatch(log.body, "^\{.*\}$")
          # Promote level to standard severity_text
          - set(log.severity_text, log.attributes["level"]) where log.attributes["level"] != nil
          # Set clean message as body
          - set(log.body, log.attributes["message"]) where log.attributes["message"] != nil
          - delete_key(log.attributes, "message")
```
