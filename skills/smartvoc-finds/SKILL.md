---
name: finds
description: Manage SmartVOC findings - view, count, update, and bulk-correct AI categorization errors. Use when reviewing AI outputs, correcting hallucinations, or managing items that need human review.
allowed-tools: Bash(source *smartvoc-api.sh*) Bash(curl *)
---

## SmartVOC Finds

Finds are items needing human review - AI outputs that don't match expected categories (hallucinations), null values, or items needing correction. Stored per client by `client_slug`.

### Count Finds

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/finds/CLIENT_SLUG/count" | smartvoc_format
```

Add query params: `?status=pending`, `?field=motivo_llamada`

### List Finds

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/finds/CLIENT_SLUG?limit=50" | smartvoc_format
```

Supports `limit`, `offset`, `status`, `field` params.

### Get Transcription for a Find

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/finds/CLIENT_SLUG/transcription?custom_id=CUSTOM_ID&conversation_id=CONV_ID" | smartvoc_format
```

### Download Finds as JSON

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/finds/CLIENT_SLUG/download-json" | smartvoc_format
```

### Update Finds (Correct AI Outputs)

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/finds/CLIENT_SLUG/update" '{
  "updates": {
    "FIND_ID_1": {"motivo_llamada": "Consulta de factura", "sentimiento": "Neutro"},
    "FIND_ID_2": {"motivo_llamada": "Reclamo"}
  }
}' | smartvoc_format
```

### Send Finds Back for Reprocessing

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/finds/CLIENT_SLUG/send-conversation" '{"findingIds":["FIND_ID_1","FIND_ID_2"]}' | smartvoc_format
```

### Upload Corrected Finds (Bulk)

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
curl -s -X POST -H "X-API-Key: $SMARTVOC_API_KEY" \
  -F "file=@/path/to/corrected.json" \
  "${SMARTVOC_API_URL}/finds/CLIENT_SLUG/upload-json" | smartvoc_format
```

### Retry Status

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/finds-retry/CLIENT_SLUG" | smartvoc_format
smartvoc_get "/finds-retry/all-clients" | smartvoc_format
```

### Typical Review Workflow

1. Count finds: `GET /finds/SLUG/count`
2. List them: `GET /finds/SLUG?limit=50`
3. Read transcription to verify: `GET /finds/SLUG/transcription?custom_id=X`
4. Correct: `POST /finds/SLUG/update` with corrections
5. Verify count decreased
