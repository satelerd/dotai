---
name: say
description: Hablarle a Daniel en voz alta usando ElevenLabs (voz chilena). Usar cuando necesites su atención urgente, quieras confirmar que algo terminó, o simplemente quieras decirle algo en voz alta. También funciona cuando el usuario pide "dime algo en voz alta", "habla", "reproduce", etc.
allowed-tools: Bash(sag *)
---

## Cómo hablarle a Daniel en voz alta

Usa `sag` para convertir texto a voz con acento chileno. La API key y voice ID ya están configurados como variables de entorno — no necesitas pasarlos explícitamente.

### Uso básico

```bash
sag speak "Lo que quieras decirle a Daniel"
```

### Voces disponibles (chilenas)

| Voz | ID | Estilo |
|-----|----|--------|
| Cristian Cornejo (default) | `ClNifCEVq1smkl4M3aTk` | Masculino, profesional, chileno |
| Vale Chile | `8XmnJFXynxUN7hZH7q3a` | Femenino, chileno |

### Cambiar voz

```bash
sag speak --voice-id 8XmnJFXynxUN7hZH7q3a "Hola Daniel"
```

### Cuándo usar esta skill

- **Tarea larga terminó**: Avisarle que el proceso completó sin que tenga que estar mirando la pantalla
- **Error crítico**: Algo falló y necesita atención inmediata
- **Confirmación**: Cuando el usuario pidió "dime cuando termines"
- **Atención urgente**: Cualquier situación donde un texto en pantalla no es suficiente

### Estilo recomendado

Habla como chileno, natural y directo. Puedes ser un poco flaite si el contexto lo amerita. Evita texto muy largo — máximo 2-3 oraciones para que no sea tedioso.

### Ejemplos

```bash
# Alerta de tarea terminada
sag speak "Oye Daniel, terminé el deploy. Quedó todo bien, puedes revisar."

# Error urgente
sag speak "Huevón, hay un error en producción. Necesito que me revises esto luego."

# Motivación
sag speak "Sigue no más compadre, que esto va quedando bien."
```
