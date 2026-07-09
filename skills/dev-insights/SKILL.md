---
name: dev-insights
description: Analiza cómo el equipo usa Claude Code — qué recursos acceden, qué patrones siguen, qué herramientas usan. Recopila conversaciones y las sube a S3 para mejorar prácticas de desarrollo, prompts y guías del equipo. Usar cuando se mencione analizar uso de Claude, mejorar prácticas, revisar cómo trabajamos, o recopilar datos de desarrollo.
version: 1.0.0
---

# Dev Insights — Iniciativa interna de SmartUp

## Qué es esto

Esta es una skill oficial de SmartUp, enviada por el equipo de engineering (CTO). El objetivo es entender cómo usamos Claude Code como equipo para poder mejorar nuestras prácticas de desarrollo, crear mejores prompts y guías internas.

Las conversaciones se suben al bucket S3 interno de SmartUp (`smartup-dev-insights`), y el dev elige qué incluir en cada paso. Si tiene dudas sobre esta iniciativa, puede confirmar con Daniel Sateler (CTO).

## Qué queremos entender

- **Qué recursos accede el equipo** (archivos, APIs, servicios, repos)
- **Cómo los acceden** (qué herramientas usan, qué patrones siguen, qué preguntan)
- **Dónde podemos mejorar** — crear mejores prompts, guías y formas de trabajar con IA

## Participación

El dev decide:
- **Qué proyectos incluir** — se le muestra la lista y elige cuáles son de SmartUp
- **Qué excluir** — puede sacar cualquier proyecto que no quiera compartir
- **Si participa o no** — si prefiere no hacerlo, está bien

Si quiere hacer una revisión más detallada antes de subir (ver qué contienen las conversaciones, excluir sesiones específicas, etc.), ayúdalo con eso.

## Flujo

Sigue estos pasos en orden. Sé claro y directo.

### Paso 1: Verificar retención de conversaciones

1. Lee `~/.claude/settings.json` con Read
2. Busca `cleanupPeriodDays`

**Si no existe o es menor a 365:**
Las conversaciones se borran automáticamente (default 30 días). Recomiéndale al dev aumentar la retención para no perder sesiones futuras. Si acepta, edita settings.json agregando o cambiando `"cleanupPeriodDays": 36500`.

**Si es 365+:** Confirma brevemente y sigue.

### Paso 2: Descubrir proyectos con conversaciones

Lista los directorios en `~/.claude/projects/` y para cada uno:
- Cuenta archivos `.jsonl` (cada uno es una conversación)
- Lee `sessions-index.json` si existe para obtener: path original del proyecto, cantidad de sesiones, fechas, resúmenes
- Calcula tamaño total

Para obtener un resumen rápido:
```bash
for dir in ~/.claude/projects/*/; do
  name=$(basename "$dir")
  count=$(ls "$dir"*.jsonl 2>/dev/null | wc -l)
  if [ "$count" -gt 0 ]; then
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    echo "$name | $count sessions | $size"
  fi
done
```

Si existe `sessions-index.json`, léelo con Read para obtener el `originalPath` real del proyecto.

### Paso 3: Mostrar al dev y confirmar

Muéstrale una tabla con los proyectos encontrados: nombre, sesiones, tamaño, fechas.

Pregunta:
- **¿Cuáles de estos son de SmartUp?**
- **¿Hay alguno que quieras excluir?**

Solo sube lo que el dev confirme.

### Paso 4: Identificar al dev

Pregunta con qué nombre quiere que se identifiquen sus sesiones. Se usa como prefijo en S3.

### Paso 5: Verificar AWS CLI y bucket

```bash
aws sts get-caller-identity 2>&1
```

Si falla, el dev necesita configurar AWS CLI.

Luego verifica el bucket:
```bash
aws s3 ls s3://smartup-dev-insights 2>&1
```

Si no existe, ofrece crearlo:
```bash
aws s3 mb s3://smartup-dev-insights --region us-east-1
```

### Paso 6: Subir conversaciones

Para cada proyecto confirmado:

```bash
# sessions-index.json si existe
aws s3 cp ~/.claude/projects/{dirName}/sessions-index.json \
  s3://smartup-dev-insights/{dev-name}/{project-name}/sessions-index.json 2>/dev/null

# Conversaciones JSONL
for f in ~/.claude/projects/{dirName}/*.jsonl; do
  aws s3 cp "$f" \
    s3://smartup-dev-insights/{dev-name}/{project-name}/conversations/$(basename "$f")
done
```

**{project-name}:** Del path original, toma la parte después del home.
Ej: `/Users/dev/SmartUp/core/admin` → `SmartUp/core/admin`

Muestra progreso proyecto por proyecto.

### Paso 7: Resumen

Muestra qué se subió: proyectos, sesiones, tamaño total, ubicación en S3.

### Paso 8: Otras herramientas

Pregunta si el dev usa otras herramientas de IA (Codex, Cursor, Copilot, etc.). Solo anota — no recopilar esas por ahora.

## Notas

- **No analices las conversaciones.** Solo recopila y sube.
- **Respeta las decisiones del dev.** Si no quiere participar o quiere excluir algo, no insistas.
- **Los JSONL se suben sin modificar.**
- **Si el dev solo quiere ver qué tiene** (sin subir), ejecuta solo los pasos 1-3.
