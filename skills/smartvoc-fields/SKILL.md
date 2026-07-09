---
name: fields
description: Manage SmartVOC custom fields, field groups, categories, and discoveries. Use when configuring what data to extract from conversations - creating fields, editing categories, viewing discoveries (non-recognized items).
allowed-tools: Bash(source *smartvoc-api.sh*) Bash(curl *)
---

## SmartVOC Fields & Categories

Fields define what data the AI extracts from conversations (e.g., "motivo_llamada", "sentimiento"). Fields are organized in **groups**, each field can have **categories** (valid values). **Discoveries** are AI outputs that don't match any category.

### List Field Groups

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-smartvoc-fields-group?clientName=CLIENT_NAME&clientId=CLIENT_ID" | smartvoc_format
```

### Get All Fields (Simple)

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/smartvoc-fields?clientId=CLIENT_ID&clientName=CLIENT_NAME" | smartvoc_format
```

### Get Categories Per Field

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-categories-per-field?clientName=CLIENT_NAME&fieldName=FIELD_NAME" | smartvoc_format
```

### Get Master Category List

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/get-master-category-list?clientName=CLIENT_NAME" | smartvoc_format
```

### Create a Field Group

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/create-smartvoc-fields-group" '{
  "clientId": CLIENT_ID,
  "clientName": "CLIENT_NAME",
  "fieldName": "GROUP_NAME",
  "fieldAndCategories": []
}' | smartvoc_format
```

### Add a Field to a Group

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/create-smartvoc-field" '{
  "clientId": CLIENT_ID,
  "fieldGroupId": FIELD_GROUP_ID,
  "name": "motivo_llamada",
  "description": "El motivo principal por el que el cliente llamo",
  "example": "consulta de factura"
}' | smartvoc_format
```

### Edit a Field

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_put "/edit-smartvoc-fields" '{
  "clientId": CLIENT_ID, "fieldId": FIELD_ID,
  "name": "motivo_llamada", "description": "Updated", "example": "Updated"
}' | smartvoc_format
```

### Update Generated Categories

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_put "/update-smartvoc-generated-fields" '{
  "clientId": CLIENT_ID,
  "fieldGroupId": FIELD_GROUP_ID,
  "generatedFieldsAndCategoriesId": GENERATED_ID,
  "categories": {
    "motivo_llamada": ["Consulta de factura", "Reclamo", "Solicitud de servicio"],
    "sentimiento": ["Positivo", "Neutro", "Negativo"]
  }
}' | smartvoc_format
```

### Get Discoveries (Non-Recognized Categories)

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_get "/client-discoveries?clientName=CLIENT_NAME" | smartvoc_format
smartvoc_get "/get-discoveries-summary?clientName=CLIENT_NAME" | smartvoc_format
```

### AI-Generated Categories

```bash
source "${CLAUDE_SKILL_DIR}/../bin/smartvoc-api.sh"
smartvoc_post "/create-category-generation" '{
  "clientName":"CLIENT_NAME","clientId":CLIENT_ID,
  "conversationIds":["CONV_ID"],"agentName":"AGENT_NAME"
}' | smartvoc_format
```
