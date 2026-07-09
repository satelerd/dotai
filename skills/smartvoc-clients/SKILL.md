---
name: clients
description: Manage SmartVOC clients - list all clients, view client configuration, create new clients, and update settings (agents, models, transcription, auto-processing). Use when working with client/organization data.
allowed-tools: Bash(source *smartvoc-api.sh*) Bash(curl *)
---

## SmartVOC Client Management

SmartVOC organizes data by **client** (e.g., "Gasco", "Sura"). Each client has its own dynamic database tables identified by a `clientSlug`. No DELETE operations available by design.

### List All Clients

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-all-smartvoc-clients" | smartvoc_format
```

Returns `clientId`, `clientName`, `clientSlug`, `hoursHired` for each client.

### View Client Details

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-smartvoc-client-details?clientName=CLIENT_NAME" | smartvoc_format
```

Returns full config: agents, models, providers, temperatures, transcription, copilot table, etc.

### View Client by ID

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-smartvoc-client-details-1/CLIENT_ID" | smartvoc_format
```

### Create a New Client

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/create-smartvoc-client" '{
  "clientName": "CLIENT_NAME",
  "hoursHired": 100
}'  | smartvoc_format
```

This creates all dynamic tables for the client (Conversations, Categories, Fields, etc.).

### Update Client Configuration

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_put "/update-smartvoc-client-details" '{
  "clientName": "CLIENT_NAME",
  "autoProcessingAgent": [{"agentName":"AGENT","fieldGroupId":"FG_ID","categoryGroupId":"CG_ID","temperature":0.1,"model":"gpt-4o-mini","provider":"azure"}],
  "autoReviewerAgent": "REVIEWER_AGENT",
  "autoPostReviewerAgent": "POST_REVIEWER_AGENT",
  "reviewModel": "gpt-4o-mini",
  "reviewProvider": "azure",
  "categorizationModel": "gpt-4o-mini",
  "categorizationProvider": "azure",
  "temperatureReview": 0.1,
  "temperatureCategorization": 0.1,
  "workHoliday": false,
  "copilotTableName": "CopilotTable__ClientSlug"
}' | smartvoc_format
```

### Update Hours

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_put "/update-smartvoc-client-hours" '{"clientId": CLIENT_ID, "hoursHired": 200}' | smartvoc_format
```

### List All Agents

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/agents" | smartvoc_format
```

### Configuration Fields Reference

| Field | Type | Description |
|-------|------|-------------|
| `autoProcessingAgent` | JSON array | Agent configs for auto-processing |
| `autoReviewerAgent` | string | Agent for review tier 1 |
| `autoPostReviewerAgent` | string | Agent for review tier 2 |
| `reviewModel` / `categorizationModel` | string | AI model name |
| `reviewProvider` / `categorizationProvider` | string | "azure", "openai", "bedrock" |
| `temperatureReview` / `temperatureCategorization` | float | 0.0-1.0 |
| `workHoliday` | boolean | Process on Chilean holidays/weekends |
| `copilotTableName` | string | Output table for clean data |
| `TranscriptionModel` | object | {provider, model, diarization, hotwords} |
