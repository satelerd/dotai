---
name: processing
description: Run and monitor SmartVOC analysis pipeline - trigger categorization, run reviews and post-reviews, check batch status, refresh processing, and deliver clean data via copilot. Use when you need to process conversations or check processing status.
allowed-tools: Bash(source *smartvoc-api.sh*) Bash(curl *)
---

## SmartVOC Processing Pipeline

The pipeline is: **Categorization -> Review -> Post-Review -> Copilot Delivery**

Each step creates batch jobs sent to AI providers (Azure OpenAI, OpenAI, AWS Bedrock). Batches have status: PROCESSING, COMPLETED, FAILED, CANCELLED, EXPIRED.

---

### CATEGORIZATION

#### Auto-Categorize (Recommended)

Processes all pending conversations for a client using configured settings:

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/automate-categorization?clientName=CLIENT_NAME" | smartvoc_format
```

#### Manual Categorization

For specific control over parameters:

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/create-categories-assignment" '{
  "clientName": "CLIENT_NAME", "clientId": CLIENT_ID,
  "conversationIds": ["CONV_ID_1"],
  "fieldGroupId": FG_ID, "categoryGroupId": CG_ID,
  "agentName": "AGENT", "model": "gpt-4o-mini", "provider": "azure",
  "temperature": 0.1, "strictMode": false, "thinkingMode": "none"
}' | smartvoc_format
```

#### Batch All Pending (All Clients)

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/smartvoc-categorization/batch-all-pending" | smartvoc_format
```

**Warning:** Processes ALL eligible clients.

#### Check Eligible Clients

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-eligible-automation-clients" | smartvoc_format
```

---

### ANALYSIS STATUS

#### Get Analysis Results

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/retrieve-analysis-v2?clientName=CLIENT_NAME" | smartvoc_format
```

#### List Batch IDs

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-smartvoc-batch-ids?clientName=CLIENT_NAME" | smartvoc_format
```

#### Refresh Batch Status

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/refresh-generative-analysis-batch" '{"clientName":"CLIENT_NAME","batchId":"BATCH_ID"}' | smartvoc_format
```

#### Refresh Auto-Processing Status

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/refresh-autoprocessing-status?clientName=CLIENT_NAME" | smartvoc_format
```

---

### REVIEWS

#### Run Full Review + Post-Review Pipeline

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/run-all-reviews-postreviews" '{"clientName":"CLIENT_NAME"}' | smartvoc_format
```

#### List Reviews

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-all-auto-reviews?clientName=CLIENT_NAME" | smartvoc_format
```

#### Refresh Review Status

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/refresh-review-batches-status?clientName=CLIENT_NAME" | smartvoc_format
```

#### List Post-Reviews

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-all-auto-post-reviews?clientName=CLIENT_NAME" | smartvoc_format
```

#### Refresh Post-Review Status

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/refresh-post-review-batches-status?clientName=CLIENT_NAME" | smartvoc_format
```

---

### COPILOT DELIVERY

Deliver clean processed data to the copilot output table:

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/copilot-automate-background" | smartvoc_format
```

---

### SYNC BATCH STATUS (Bedrock)

When batches complete in Bedrock but SmartVOC still shows PROCESSING, sync the status:

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/sync-generative-analyses" '{"clientName":"CLIENT_NAME"}' | smartvoc_format
```

You can also check Bedrock job status directly via AWS CLI:
```bash
aws bedrock get-model-invocation-job --job-identifier "JOB_ARN" --region us-east-1
aws bedrock list-model-invocation-jobs --region us-east-1 --status-equals Submitted
```

---

### TYPICAL FULL PIPELINE

1. Check eligible clients: `/get-eligible-automation-clients`
2. Trigger categorization: `/automate-categorization?clientName=X`
3. Monitor: `/get-smartvoc-batch-ids?clientName=X` until COMPLETED
4. Sync if needed: `/sync-generative-analyses` (for Bedrock batches)
5. Run reviews: `/run-all-reviews-postreviews`
6. Check reviews: `/get-all-auto-reviews?clientName=X`
7. Deliver: `/copilot-automate-background`

---

### COMPLETE END-TO-END WORKFLOW (New Analysis from Scratch)

This is the full workflow for setting up a new analysis project in SmartVOC, from creating the client to getting results. Learned from the DevInsights project (2026-04-08).

#### Phase 1: Setup Client

```bash
# 1. Create client
smartvoc_post "/create-smartvoc-client" '{"clientName": "MyClient", "hoursHired": null}'

# 2. Verify
smartvoc_get "/get-all-smartvoc-clients" | smartvoc_format
```

#### Phase 2: Create Agent (via admin-manage MCP)

The agent contains the system prompt that instructs the LLM how to analyze conversations. Key rules:

- Use `{{fields}}` and `{{categories}}` as placeholders — SmartVOC replaces them with hyperparameters at runtime
- NEVER hardcode fields/categories in the prompt — they must come from hyperparameters
- The prompt should enforce a strict output format: `{"field_name": {"category_or_text": "evidence"}}`
- Include a CORRECT example and an INCORRECT example in the prompt
- Include Phase 2 (review/correction) instructions for self-QA
- Agent is created via `mcp__admin-manage__admin_create_agent` with name, displayName, prompt, defaultLanguage

Example agent prompt structure:
```
[Context about what conversations are being analyzed]
[Task description]
[STRICT output format rules with examples]
[Per-field instructions]
[Phase 2: Review and correction]
[{{fields}} and {{categories}} placeholders at the end]
```

#### Phase 3: Define Fields and Categories

```bash
# Create field group with all fields embedded
smartvoc_post "/create-smartvoc-fields-group" '{
  "clientId": CLIENT_ID,
  "clientName": "MyClient",
  "fieldName": "my_analysis_v1",
  "fieldAndCategories": "[{\"fieldId\":1,\"name\":\"field_name\",\"description\":\"...\",\"example\":\"...\"}]"
}'
```

Fields have: fieldId, name, description, example. Categories are passed as hyperparameters in the categorization request, NOT stored in the field group.

**Important**: Delete empty field groups if you accidentally create them:
```bash
smartvoc_post "/remove-smartvoc-fields-group" '{"clientName":"MyClient","fieldGroupId":N}'
```

#### Phase 4: Upload Conversations

Format required per conversation:
```json
{
  "conversationId": "unique-id",
  "conversation": [
    {"role": "metadata", "content": {"id": "...", "datetime": "...", "duration": "HH:MM:SS"}},
    {"role": "user", "content": "message text"},
    {"role": "assistant", "content": "response text"}
  ]
}
```

Upload:
```bash
smartvoc_post "/smartvoc-conversations" '{
  "clientName": "MyClient",
  "clientId": "CLIENT_ID",
  "batchCustomName": "batch_name",
  "conversations": [...]
}'
```

**Tips**:
- For large payloads, write to temp file and use `curl -d @filepath`
- Max ~5-10 conversations per batch to avoid gateway timeouts
- Tool calls in Claude Code conversations should be flattened to readable text like `[Tool: Bash] command`

#### Phase 5: Launch Categorization

```bash
smartvoc_post "/create-categories-assignment" '{
  "conversationsId": "BATCH_UUID",
  "clientName": "MyClient",
  "batchPlatform": "bedrock",
  "model": "claude-4-5-haiku",
  "provider": "bedrock",
  "temperature": 0.1,
  "agentName": "my-agent-name",
  "hyperparameters": {
    "fields": "[{\"name\":\"field1\",...}]",
    "categories": "{\"field1\":[\"cat1\",\"cat2\"],...}"
  }
}'
```

**Provider options**:
- `bedrock` + `claude-4-5-haiku`: Cheapest ($0.40/$2.00 per MTok batch). Good quality.
- `bedrock` + `claude-4-5-sonnet`: Better quality ($1.50/$7.50 per MTok batch). 4x more expensive.
- `openai` + `gpt-4o-mini`: Requires Azure/OpenAI API key configured on server.

**Important**: The `hyperparameters.fields` and `hyperparameters.categories` MUST be JSON strings (not objects). SmartVOC's `prompt.compile()` replaces `{{fields}}` and `{{categories}}` with these values.

#### Phase 6: Monitor and Retrieve

```bash
# Check batch status
smartvoc_get "/get-smartvoc-batch-ids?clientName=MyClient"

# For Bedrock batches, sync status
smartvoc_post "/sync-generative-analyses" '{"clientName":"MyClient"}'

# Or check directly via AWS CLI
aws bedrock get-model-invocation-job --job-identifier "JOB_ARN" --region us-east-1

# Retrieve results
smartvoc_get "/retrieve-analysis-v2?clientName=MyClient"
```

Bedrock batch jobs can take 5min to several hours depending on queue load.

#### Phase 7: Review and Deliver

```bash
# Run review pipeline
smartvoc_post "/run-all-reviews-postreviews" '{"clientName":"MyClient"}'

# Deliver to copilot table
smartvoc_get "/copilot-automate-background"
```

#### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| 401 on GET endpoints | `API_KEY` env var not set on server | Use backend.dev.smartvoc.ai or ask admin to set env var |
| `information_schema.tables` error | Bug in `/smartvoc-fields` endpoint | Use `/get-smartvoc-fields-group` instead |
| `Unconsumed column names: batchOutput` | Table schema mismatch | Sync endpoint needs table migration |
| Output format inconsistent | Prompt not strict enough | Use `{{fields}}`/`{{categories}}` placeholders, enforce dict format with examples |
| Bedrock batch stuck in Submitted | AWS queue congestion | Wait — SLA is up to 24h |
| Large payload fails with curl | Argument too long for shell | Write payload to temp file, use `curl -d @filepath` |
