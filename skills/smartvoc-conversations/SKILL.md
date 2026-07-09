---
name: conversations
description: Manage SmartVOC conversations - list conversation batches, upload new conversations, check hours usage, view stats, and update processing status. Use when working with conversation data or monitoring usage.
allowed-tools: Bash(source *smartvoc-api.sh*) Bash(curl *)
---

## SmartVOC Conversations

Conversations are uploaded in batches to each client. Each batch has a `batchCustomName` and goes through: upload -> categorization -> review -> post-review -> copilot delivery.

### List Conversations

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/smartvoc-conversations?clientName=CLIENT_NAME&clientId=CLIENT_ID" | smartvoc_format
```

Returns batches with `batchCustomName`, `conversationsQuantity`, `conversationId`, `createdAt`, `autoProcessingStatus` (NOT_PROCESSED, PROCESSING, PROCESSED, ERROR).

### Upload Conversations

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/smartvoc-conversations" '{
  "clientName": "CLIENT_NAME",
  "clientId": CLIENT_ID,
  "batchCustomName": "BATCH_NAME",
  "conversations": [
    {"custom_id": "conv_001", "conversation": {"text": "...", "metadata": {}}},
    {"custom_id": "conv_002", "conversation": {"text": "...", "metadata": {}}}
  ]
}' | smartvoc_format
```

### Update Conversation Status

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_put "/update-conversation-status" '{
  "clientName": "CLIENT_NAME",
  "conversationId": "CONVERSATION_ID",
  "status": "NOT_PROCESSED"
}' | smartvoc_format
```

### Monthly Hours

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/smartvoc-conversations/monthly-hours?clientName=CLIENT_NAME" | smartvoc_format
```

### All Clients Hours

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/smartvoc-conversations/all-clients-hours-calculated" | smartvoc_format
```

### Client Hours by Month

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/smartvoc-conversations/client-hours/CLIENT_ID?month=YYYY-MM" | smartvoc_format
```

### Available Months

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/smartvoc-conversations/available-months?clientName=CLIENT_NAME" | smartvoc_format
```

### Monthly Overview Stats

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/smartvoc-stats/monthly-overview?clientName=CLIENT_NAME" | smartvoc_format
```

### Download Unified Batch

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/download-unified-batch" '{"clientName":"CLIENT_NAME","batchIds":["ID1","ID2"]}' | smartvoc_format
```

### System Health

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/health" | smartvoc_format
smartvoc_get "/check-holidays-status" | smartvoc_format
```
