---
name: smartup-dual-eks-deploy
description: Use when updating a SmartUp repo's GitHub Actions workflow to deploy correctly to both EKS clusters during the AWS migration. Covers current cluster names, namespace/deployment drift between migration and prod, rollout checks, and cutover-safe rules so the workflow updates the real live deployment in prod instead of stale names.
---

# SmartUp Dual EKS Deploy

Use this skill when a SmartUp repo needs its GitHub Actions deployment workflow created or updated for dual deploy during the `smartup-migration` -> `smartup-prod-eks` transition.

Read [references/mappings.md](references/mappings.md) before editing a workflow. That file is the current migration map and includes the repos already audited, the current prod targets, and the repos that still need dual deploy.

## Goal

Make the repo deploy to both:
- `smartup-migration`
- `smartup-prod-eks`

The workflow must update the real live deployment in `prod`, not a stale or parallel deployment.

## Source Patterns

Use these repos as the current good patterns:
- `/Users/sat/SmartUp/core/agente-0001/.github/workflows/deploy.yml`
- `/Users/sat/SmartUp/core/multi-channel/.github/workflows/multichannel-ci-cd.yml`

Use those patterns for:
- one build/push job
- one deploy job with a cluster matrix
- branch-aware mapping for `main` vs `dev`
- rollout verification per cluster

Do not cargo-cult blindly. Many repos changed namespace, deployment name, service name, or container name in `prod`.

## Rules

1. Keep one image build and deploy that image to both clusters.
2. Use a matrix or equivalent explicit per-cluster mapping.
3. Map each cluster to its real namespace, deployment name, and container name.
4. For `prod`, target the deployment that actually backs the live service/ingress.
5. Preserve branch semantics:
- `main` -> production deployment/image tag
- `dev` -> development deployment/image tag
6. Fail fast if the target deployment does not exist.
7. After deploy, run:
- `kubectl rollout restart`
- `kubectl rollout status`
- `kubectl get pods` for the expected label
8. If the workflow patches secrets or env vars, keep cluster-specific values explicit.
9. If the repo uses build args with public URLs or legacy service names, verify they are still correct for `prod`.

## Procedure

1. Open the current workflow.
2. Compare it with the audited mappings in [references/mappings.md](references/mappings.md).
3. Identify:
- migration namespace/deployment/container
- prod namespace/deployment/container
- `main` and `dev` targets
4. Convert the deploy job to cluster-aware logic.
5. Keep the existing build and ECR logic unless it is clearly broken.
6. Add verification output that makes the mapping obvious in CI logs.
7. Check whether the repo also owns secrets/config changes that differ by cluster.
8. Do not change ingress or DNS from this workflow task.

## High-Risk Pitfalls

- Updating `new-admin` instead of `admin`
- Reusing `smartup` namespace in `prod` when the service moved to `shapeup`, `smartorders`, `gadgets`, or `utils`
- Reusing old deployment names from `migration`
- Using public URLs in `prod` when the service should use cluster DNS
- Assuming a repo owns the full product when another repo deploys a frontend or sidecar for the same hostname

## Minimum Validation

For every workflow change, verify:
- branch-to-target mapping is explicit
- both clusters are configured
- `prod` target matches the live deployment from the current cluster state
- rollout commands point to the same deployment that `set image` touched
- the logs print the chosen cluster, namespace, deployment, and container

## Output

When using this skill, produce:
- the workflow change
- a short note listing the exact target mapping used
- any open questions if the repo is not the only owner of a hostname or product surface






----


# SmartUp Dual Deploy Mappings

Snapshot based on the cluster/workflow audit done on `2026-03-25`.

## Canonical Good Examples

Use these as the reference implementation style:
- `agente-0001`: `/Users/sat/SmartUp/core/agente-0001/.github/workflows/deploy.yml`
- `multi-channel`: `/Users/sat/SmartUp/core/multi-channel/.github/workflows/multichannel-ci-cd.yml`

They already:
- build once
- deploy to both clusters
- map cluster + branch to the right deployment
- verify rollout after deployment

## Repo Audit

### Already Dual

| Repo | Workflow | Notes |
|---|---|---|
| `agente-0001` | `/Users/sat/SmartUp/core/agente-0001/.github/workflows/deploy.yml` | Good dual pattern |
| `multi-channel` | `/Users/sat/SmartUp/core/multi-channel/.github/workflows/multichannel-ci-cd.yml` | Good dual pattern, but runtime config still needs `SMARTUP_SERVER_URL` review |

### Needs Update

| Repo | Workflow | Current State | Migration Target | Prod Target |
|---|---|---|---|---|
| `admin` | `/Users/sat/SmartUp/core/admin/.github/workflows/deploy-aws.yml` | Touches both clusters but wrong prod target | `smartup/smartup-admin` | `smartup/admin` |
| `tools` | `/Users/sat/SmartUp/core/tools/.github/workflows/tool-server-cicd.yml` | Migration only | `smartup/tool-server-deployment`, `smartup/tool-server-dev-deployment` | `smartup/tool-server-deployment`, `smartup/tool-server-dev-deployment` |
| `ocr-service` | `/Users/sat/SmartUp/core/tools/.github/workflows/ocr-service-cicd.yml` | Migration only | `smartup/ocr-service-deployment`, `smartup/ocr-service-dev-deployment` | `gadgets/ocr-service` |
| `ax` | `/Users/sat/SmartUp/core/ax/.github/workflows/ax-ci-cd.yml` | Migration only | `smartup/ax-deployment`, `smartup/ax-dev-deployment` | `smartup/ax`, `smartup/ax-dev` |
| `SmartOrders` | `/Users/sat/SmartUp/smartorders/SmartOrders/.github/workflows/cd-deploy.yml` | Migration only | `smartup/smartorders-deployment`, `smartup/smartorders-dev` | `smartorders/orders-deployment`, `smartorders/orders-dev-deployment` |
| `ShapeUp` | `/Users/sat/SmartUp/core/ops-smartup/shape-up/.github/workflows/deploy-aws.yml` | Migration only | `smartup/shapeup` | `shapeup/shapeup` |
| `smartvoc-backend` | `/Users/sat/SmartUp/_blacksmith-rollout10/smartvoc-backend/.github/workflows/CICD.yml` | Migration only | `smartvoc/smartvoc-deployment`, `smartvoc/smartvoc-dev-deployment` | `smartvoc/smartvoc-deployment`, `smartvoc/smartvoc-dev-deployment` |

## Branch Mapping

Default branch semantics observed:

| Branch | Migration | Prod |
|---|---|---|
| `main` | production deployment | production deployment |
| `dev` | dev deployment | dev deployment if it exists |

Do not assume `prod` dev deployments always exist. Verify before wiring them into the workflow.

## Known Live Prod Targets

### SmartUp namespace

| Service | Prod Deployment | Service |
|---|---|---|
| Myria | `myria` | `myria-service` |
| Myria Dev | `myria-dev` | `myria-dev-service` |
| Admin | `admin` | `admin-service` |
| New Admin | `new-admin` | `new-admin-service` |
| Multichannel | `multichannel` | `multichannel-service` |
| Multichannel Dev | `multichannel-dev` | `multichannel-dev-service` |
| Tool Server | `tool-server-deployment` | `tool-server-service` |
| Tool Server Dev | `tool-server-dev-deployment` | `tool-server-dev-service` |
| AX | `ax` | `ax-service` |
| AX Dev | `ax-dev` | `ax-dev-service` if present, otherwise verify actual service |

### Other namespaces

| Product | Prod Namespace | Prod Deployment |
|---|---|---|
| ShapeUp | `shapeup` | `shapeup` |
| SmartOrders API | `smartorders` | `orders-deployment` |
| SmartOrders Dev | `smartorders` | `orders-dev-deployment` |
| OCR Service | `gadgets` | `ocr-service` |
| SmartVOC Backend | `smartvoc` | `smartvoc-deployment` |
| SmartVOC Backend Dev | `smartvoc` | `smartvoc-dev-deployment` |

## Special Cases

### `admin`

`admin.smartup.lat` in `prod` is backed by:
- ingress: `smartup/smartup-admin-ingress`
- service: `smartup/admin-service`
- deployment: `smartup/admin`

The current workflow updates `new-admin`, which is not the live canonic target.

### `multichannel`

The workflow is dual already, but runtime still needs confirmation because `SMARTUP_SERVER_URL` comes from `multichannel-secrets`.

In `prod`, the intended internal dependency is:
- `http://myria-service.smartup.svc.cluster.local:5001/api`

Do not treat the workflow as the whole fix for multichannel.

### `SmartOrders`

The API repo is not the whole cutover. `orders.getsmartup.ai` depends on:
- `smartorders/orders-deployment`
- `smartorders/orders-dashboard`
- functioning cronjobs/imports

A workflow change for the API repo alone does not mean the product is cutover-ready.

### `SmartVOC`

The backend repo is only one piece. The product still has blockers in `prod`:
- `dashboards-backend` failing
- `auditorias-backend` failing
- batch jobs still unstable

Also verify whether additional repos own:
- frontends
- auditorias backend/frontend
- dashboards backend/frontend
- `smartvoc-frontend-v2`
- `nexus-voc-api`

## Implementation Template

Use this shape when updating a migration-only workflow:

1. Keep `build-and-push` mostly intact.
2. Replace single-cluster deploy with:
- `strategy.matrix.include`
- one entry per cluster
- explicit namespace/deployment/container names
3. In the deploy step:
- choose image tag from branch
- choose deployment/container from matrix
- `aws eks update-kubeconfig --name <cluster>`
- `kubectl set image`
- `kubectl rollout restart`
- `kubectl rollout status`
4. Print:
- cluster
- namespace
- deployment
- container

## Prompt To Give Another Agent

Use this prompt when asking another agent to update a repo:

```text
Use the smartup-dual-eks-deploy skill. Update this repo's GitHub Actions workflow so it deploys to both EKS clusters during the migration:
- smartup-migration
- smartup-prod-eks

Requirements:
- preserve the existing build/push behavior unless clearly broken
- use the audited target mapping from the skill reference
- in prod, target the real live deployment, not a stale parallel deployment
- keep main/dev branch mapping explicit
- verify rollout after set image
- do not change DNS or ingress in this task

At the end, tell me:
- exact mapping used per cluster and branch
- any open questions about missing prod dev targets, namespaces, or sibling repos
```
