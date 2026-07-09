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
