---
name: codex-delegate
description: Delegar trabajo a Codex CLI (gpt-5.6-terra/sol/luna) desde Claude Code — bulk work con spec clara, verificación de UI, reviews independientes, research con web. Usar cuando una tarea calce con el perfil de delegación de la sección "Modelos y delegación a Codex" del CLAUDE.md, o cuando el usuario pida explícitamente usar Codex / GPT.
---

# Delegar a Codex CLI

Codex CLI corre modelos de OpenAI de forma no-interactiva vía `codex exec`. Esta skill define cuándo delegar, con qué modelo, y la mecánica exacta verificada en esta máquina.

## Prerrequisito: versión del CLI

Requiere **codex-cli ≥ 0.144.0**. Si un modelo gpt-5.6 falla con `The 'gpt-5.6-*' model requires a newer version of Codex`, el CLI está viejo:

```bash
codex --version                      # debe ser >= 0.144.0
bun install -g @openai/codex@latest  # así se instala en las máquinas de Daniel
```

Esto es especialmente probable en máquinas que no se han actualizado (ej. mini-sat).

## Cuándo delegar

Delegar a Codex cuando la tarea es:

1. **Bulk / mecánico con spec clara** — migraciones, refactors repetitivos, análisis de datos, generación masiva. El plan de OpenAI de Daniel tiene límites generosos; esto descarga los rate limits de Claude.
2. **Verificación de UI/UX y computer use** — Codex es fuerte revisando resultados visuales y ejecutando flujos en el navegador/desktop.
3. **Review independiente** — segunda perspectiva sobre un plan o diff, además del review propio (para "Claude atascado" existe el plugin `codex:rescue`, no esta skill).
4. **Research con web** — el config de Codex tiene `web_search = "live"`.

NO delegar: decisiones de arquitectura, trabajo user-facing donde el taste importa más que el volumen (eso lo hace Claude), o tareas que dependen del contexto acumulado de esta conversación (Codex parte de cero).

## Elección de modelo

| modelo | perfil | usar para |
|---|---|---|
| `gpt-5.6-terra` | workhorse diario (~2.50/15 USD por 1M tokens) | default para todo lo delegado |
| `gpt-5.6-sol` | detalle y pulido | cuando el output delegado es user-facing |
| `gpt-5.6-luna` | barato, repetible | bulk trivial masivo (renombres, formateo) |

Reglas:
- Son defaults, no límites. **Permiso permanente de override**: si el output del modelo barato no da la talla, rehacer con un modelo mejor (o hacerlo Claude mismo) sin preguntar. Juzgar el output, no el precio.
- Pasar siempre `-m <modelo>` explícito cuando el modelo importa — el default de `~/.codex/config.toml` puede diferir entre máquinas.

## Mecánica

```bash
# Investigación / research / análisis (no escribe nada)
codex exec -s read-only -m gpt-5.6-terra "<prompt autocontenido>" </dev/null

# Implementación (escribe en el workspace)
codex exec -s workspace-write -m gpt-5.6-terra "<prompt autocontenido>" </dev/null

# Review del repo actual
codex exec review </dev/null

# Follow-up en el mismo hilo (mandar solo el delta, no repetir el prompt)
codex exec resume --last "<instrucción delta>" </dev/null
```

Detalles operativos (verificados):
- **`</dev/null` es obligatorio** al correr desde un agente: sin TTY, codex intenta leer stdin y se cuelga esperando input.
- **`--skip-git-repo-check`** si el cwd no es un dir trusted en `~/.codex/config.toml` (ej. scratchpads). `/Users/sat/code` y `/Users/sat/SmartUp` ya son trusted.
- El output llega por stdout con ruido de logs (`ERROR rmcp::transport`, deprecation warnings) — ignorarlo; la respuesta real viene después del marcador `codex`. Filtrar con `grep -v "^2026-\|deprecated"` si estorba.
- Timeout: dar al Bash tool 120–600s según el tamaño de la tarea. Para tareas largas, correr con `run_in_background`.
- Codex hereda los MCP del config de Daniel (ShapeUp, admin-manage), así que puede consultar esos sistemas directamente si el prompt se lo pide.

## Cómo escribir el prompt

Codex parte **sin ningún contexto de esta conversación**. El prompt debe ser autocontenido: rutas absolutas, el objetivo, qué significa "listo", y el formato de salida esperado.

Usar la estructura de bloques XML del plugin oficial de codex (skill `codex:gpt-5-4-prompting` — aplica igual a gpt-5.6):
- `<task>`: el trabajo concreto + contexto del repo/falla.
- `<structured_output_contract>` o `<compact_output_contract>`: forma exacta del output.
- `<verification_loop>`: obligatorio para implementación o fixes (que corra tests/build y reporte el resultado).
- `<grounding_rules>`: obligatorio para review/research (citar archivo:línea o URL, marcar hipótesis como hipótesis).
- `<action_safety>` en tareas write: mantenerse en el scope, no refactors no pedidos.

Un run = una tarea. Asks no relacionadas van en runs separados.

## Al terminar

- Verificar el resultado antes de reportarlo (si Codex implementó algo, correr los tests / mirar el diff — no confiar ciego).
- Reportar a Daniel qué se delegó, a qué modelo, y qué se verificó.
