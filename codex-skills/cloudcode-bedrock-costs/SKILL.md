---
name: cloudcode-bedrock-costs
description: Generate a local-only Cloud Code Bedrock cost report (JSON/CSV/HTML/PDF) from Claude transcript files under ~/.claude, with daily/model/workspace/session breakdowns and no AWS CLI usage.
---

# Cloud Code Bedrock Costs (Local Only)

## Cuándo usar esta skill
Usa esta skill cuando necesites analizar costos de Cloud Code **en el equipo local** donde corre Claude Code, sin consultar AWS.

Ejemplos:
- "Quiero saber cuánto gasté localmente en Bedrock"
- "Dame gasto diario y por modelo de este notebook"
- "Genera PDF ejecutivo desde mis archivos locales"

## Fuente de datos
Esta skill solo usa archivos locales en `~/.claude/projects/**/*.jsonl` (o la carpeta indicada con parámetro).

No usa AWS CLI.

## Script principal
`/Users/sat/.codex/skills/cloudcode-bedrock-costs/scripts/bedrock_user_report.py`

## Paso a paso

### 1) Ejecutar análisis local completo
```bash
python /Users/sat/.codex/skills/cloudcode-bedrock-costs/scripts/bedrock_user_report.py \
  --claude-root ~/.claude \
  --output-dir ./data/target/local_cloudcode_costs
```

### 2) Filtrar por rango de fechas
```bash
python /Users/sat/.codex/skills/cloudcode-bedrock-costs/scripts/bedrock_user_report.py \
  --claude-root ~/.claude \
  --from-date 2026-01-15 \
  --to-date 2026-02-16 \
  --output-dir ./data/target/local_cloudcode_costs
```

### 3) Validar caso SmartUp-admin (workspace filter)
```bash
python /Users/sat/.codex/skills/cloudcode-bedrock-costs/scripts/bedrock_user_report.py \
  --claude-root ~/.claude \
  --workspace-filter admin \
  --output-dir ./data/target/local_cloudcode_costs_admin
```

### 4) Revisar entregables
Se generan:
- `local_bedrock_cost_intelligence.json`
- `local_daily.csv`
- `local_models.csv`
- `local_workspaces.csv`
- `local_sessions.csv`
- `local_bedrock_cost_report.html`
- `local_bedrock_cost_report.pdf` (si Chrome/Chromium está disponible)

## Qué mide
- Costo estimado local total (USD)
- Evolución diaria
- Presión de uso en ventanas de 5 horas
- Correlación semanal contra planes de USD 20 (Cloud Code Pro y Codex Plus)
- Mix de tokens (input/output/cache)
- Ranking por modelo
- Ranking por workspace
- Top sesiones por costo
- Ahorro estimado por cache

## Metodología breve
- Deduplicación por invocación: `sessionId + message.id`.
- Costo estimado por tokens locales (`input`, `output`, `cache write`, `cache read`).
- Pricing por familia de modelo (`Haiku/Sonnet/Opus`) + multiplicadores de cache:
  - cache write = 1.25x input
  - cache read = 0.10x input

## Notas
- Este reporte es estimación analítica local; puede diferir de factura exacta AWS por precios/región/impuestos/ajustes.
- Si no hay PDF, revisa que exista Chrome/Chromium en la máquina.
- Para Codex Plus, OpenAI indica límite semanal compartido pero no publica número exacto; el reporte muestra un proxy.
