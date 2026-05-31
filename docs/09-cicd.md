# CI/CD Pipeline Design

> **Source of Truth** — Automated build, test, scan, sign, deploy pipeline design.
> Last updated: 2026-05-31

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PR Pipeline (pre-merge validation)                                      │
│                                                                         │
│  PR Opened → [lint, fmt, shellcheck] → [Terraform plan] → [Trivy scan]  │
│  → [Syft SBOM] → [Review] → Merge                                       │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  Deploy Pipeline (post-merge)                                           │
│                                                                         │
│  Merge → [Build images] → [Cosign sign] → [Push to Harbor]              │
│  → [Terraform apply] → [ArgoCD sync] → [Smoke tests] → [Done]          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  Continuous Operations                                                 │
│                                                                         │
│  Renovate Bot (automated dependency updates)                            │
│  → PR created with dep update + auto-merge if CI passes                 │
│                                                                         │
│  Drift Detection (ArgoCD)                                               │
│  → Git as source of truth → auto-reconcile                             │
└─────────────────────────────────────────────────────────────────────────┘
```

## Workflow Files

### `pr-validation.yaml`

```yaml
name: PR Validation
on:
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint YAML
        uses: ibiqlik/action-yamllint@v3
      - name: Lint Terraform
        run: |
          cd terraform/envs/dev
          terraform fmt -check -recursive
      - name: Validate Config
        run: |
          python3 scripts/validate-config.py config/demo.yaml
      - name: Security Scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          scan-ref: .
          format: sarif
          output: trivy-results.sarif
          severity: HIGH,CRITICAL
          exit-code: 1
```

### `infra-plan.yaml`

```yaml
name: Terraform Plan
on:
  pull_request:
    paths:
      - "terraform/**"
      - "config/**"

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.0
      - name: Terraform Plan
        run: |
          cd terraform/envs/dev
          terraform init
          terraform plan -out=tfplan
      - name: Post Plan Comment
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('terraform/envs/dev/tfplan', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## Terraform Plan\n\`\`\`\n${plan}\n\`\`\``
            });
```

### `deploy.yaml`

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    environment: dev
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - name: Terraform Apply
        run: |
          ./terraform/scripts/apply-all.sh --env dev --auto-approve
      - name: Wait for ArgoCD
        run: |
          sleep 60 # Wait for ArgoCD to detect changes
      - name: Health Check
        run: |
          kubectl wait --for=condition=Ready pods \
            -l app.kubernetes.io/name=vllm \
            -n ai-inference --timeout=300s
      - name: Smoke Test
        run: |
          curl -f http://llm-inference.ai-platform.svc/health
```
