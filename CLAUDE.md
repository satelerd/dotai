# Contexto del Usuario

## Sobre Daniel Sateler (sat)
- **Nombres/aliases:** Daniel Sateler, sat, SAT, sateler, daniel
- **Rol:** Cofounder y CTO en SmartUp
- **Empresa:** SmartUp - startup chilena

## Visión de SmartUp
Hacer que SmartUp pueda operar de manera autónoma con agentes. En 2021 conseguí acceso a GPT-3 y en 2023 con GPT-4 empezamos SmartUp con el objetivo de ser una empresa que opere de manera autónoma con agentes. Para lograrlo, hay que meterse en pequeñas verticales de negocio y empezar a agencializarlas (automatizar con agentes), luego tomar todas esas verticales y administrarlas con agentes.

## Productos Actuales

### SmartOrders
Agentes que automatizan la venta de distribuidoras mayoristas. Los agentes revisan stock del cliente, lista de precio, etc. y crean la orden de compra en el ERP.

### SmartVOC
Toma conversaciones de callcenter, las transcribe y las procesa con agentes para entender y analizar cosas subjetivas y auditar cosas legales o requerimientos. Son muchas horas de conversación, por lo que tiene que ser muy optimizado y usar batches.

## Arquitectura Técnica
- **Infraestructura:** Kubernetes en Azure (en proceso de migración a AWS)
- **Tipos de servidor:** NextJS o Flask
- **Múltiples repositorios/pods desplegados**

### Repositorios Principales
- **agente-0001:** Flask, endpoint "use-agent" que permite enviar mensaje a un agente, ejecutar herramientas y dar respuesta. Las tools se ejecutan en otro server llamado "tools".
- **admin:** Next, plataforma para administrar agentes. CRUD de organizaciones, API keys, agentes, tools. Permite revisar conversaciones, configurar proveedores y modelos de LLM. Tiene API (admin manage api).
- **orders:** Flask, generaliza y mantiene la lógica de tools de SmartOrders (revisar clientes, lista de precio, login, stock, ingresar órdenes, etc.)
- **smartvoc:** Varios Next y Flask que incluyen admins, dashboards, backends, etc.
- **shapeup:** Plataforma interna de organización de proyectos. Permite crear tasks, asignar responsable, equipo, proyecto, prioridad y hacer seguimiento.
- **multichannel:** Flask con URL pública, es el webhook para todos los canales (Meta Business, Kapso, SendGrid) que procesa y envía a agente-0001.

## Correcciones de Transcripción de Audio
El usuario suele enviar mensajes que son audios transcritos. Errores comunes:
- **Smartap / smartapp / SmartTab** → SmartUp
- **SmartBook / SmartBug** → SmartVOC
- **JPUB** → ShapeUp
- Si algo suena raro, preguntar para confirmar.

## Modelos y delegación a Codex

Claude puede delegar trabajo a modelos de OpenAI vía Codex CLI (`codex exec`). Defaults, no límites — con permiso permanente de override si el output no da la talla (juzgar el output, no el precio):

| modelo | costo | usar para |
|---|---|---|
| gpt-5.6-terra | muy barato (plan OpenAI generoso) | bulk/mecánico con spec clara, research con web, verificación UI |
| gpt-5.6-sol | barato | output delegado que es user-facing |
| gpt-5.6-luna | casi gratis | bulk trivial masivo |
| claude (yo) | rate limits de Anthropic | arquitectura, taste, trabajo con contexto de la conversación |

- Bulk/mecánico (migraciones, análisis de datos, refactors repetitivos): delegar a terra.
- Reviews de planes/implementaciones: Claude, opcionalmente + Codex como perspectiva independiente.
- Mecánica exacta (flags, sandbox, prompts autocontenidos): skill `codex-delegate`. Para rescatar a Claude atascado: plugin `codex:rescue`.

## Offboarding (Concepto Crítico)

**Offboarding** es el proceso de cerrar una conversación cuando el contexto se está agotando (~70%) y preparar todo para que el siguiente agente pueda continuar sin fricción.

### Por qué es importante
- Durante el trabajo surgen nuevas ideas o las tareas son muy grandes para una sesión
- El contexto acumulado es valioso y debe transferirse de forma compacta pero densa
- Sin offboarding, el siguiente agente empieza de cero y se pierde progreso

### Cuándo hacer offboarding
- Al llegar a ~70% de contexto, preguntar proactivamente al usuario
- Cuando se completa una fase lógica del trabajo
- Cuando el usuario lo solicita

### Cómo hacer offboarding
1. **Actualizar ShapeUp**: Crear tasks nuevas o agregar comentarios detallados a tasks existentes con todo el contexto relevante
2. **Preparar handoff text**: Un mensaje compacto para copiar/pegar en la nueva conversación que incluya:
   - Links a las tasks de ShapeUp relevantes
   - Resumen del estado actual
   - Qué quedó pendiente
   - Branch de git si aplica
   - Cualquier contexto técnico crítico
3. **Instrucciones claras**: El texto debe permitir al nuevo agente continuar inmediatamente

### Formato sugerido de handoff
```
## Contexto
[Resumen de 2-3 líneas de qué se estaba haciendo]

## Tasks ShapeUp
- [URL task 1] - [estado]
- [URL task 2] - [estado]

## Estado actual
- Branch: `nombre-branch`
- [Qué está listo]
- [Qué falta]

## Siguiente paso
[Acción concreta a tomar]

## Para empezar
Revisa los tasks de ShapeUp mencionados, revisa el estado de GitHub (branch, commits recientes) y revisa el código relevante. Luego puedes empezar.
```
