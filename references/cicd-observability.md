---
description: Distributed tracing for CI/CD pipelines, GitHub Actions, GitLab CI, and Jenkins runs represented as distributed trace DAGs.
metadata:
  tags: [cicd, github-actions, gitlab-ci, jenkins, pipeline-tracing, devops]
---

# CI/CD Pipeline Observability

Treating software delivery pipelines as distributed systems allows teams to trace workflow executions, diagnose test flakiness, track build bottlenecks, and correlate Git commits with production telemetry.

---

## 1. Pipeline Trace Hierarchy

```
Pipeline Run: Release Build (Root Span: SPAN_KIND_SERVER) [0s ----------------------- 120s]
├── Job 1: Lint & Security Scan (Child Span) [2s ----------------- 25s]
│   ├── Step: Gitleaks Secret Scan [3s --- 10s]
│   └── Step: Semgrep SAST Scan [11s ----- 24s]
└── Job 2: Build & Test (Child Span) [26s -------------------------------------------- 118s]
    ├── Step: Docker Build [27s ----------------- 75s]
    └── Step: Integration Tests [76s ------------------------------------------------- 117s]
        └── Span Event: Test Failure "TestPaymentGateway" (AssertionError: 504 Gateway Timeout)
```

---

## 2. Semantic Conventions for CI/CD

- `ci.pipeline.name`: Workflow name (e.g., `"release-pipeline"`).
- `ci.pipeline.run_id`: Unique run ID from GitHub Actions / GitLab.
- `ci.pipeline.run_attempt`: Run attempt number (e.g., `1`, `2` for retries).
- `vcs.repository.url`: Git repository URL.
- `vcs.revision.sha`: Commit SHA.
- `vcs.ref.branch`: Target Git branch.

---

## 3. Production Workflow Manifests
- GitHub Actions Workflow: [`github-actions-otel.yaml`](../examples/cicd/github-actions-otel.yaml)
- GitLab CI Configuration: [`gitlab-ci-otel.yaml`](../examples/cicd/gitlab-ci-otel.yaml)
