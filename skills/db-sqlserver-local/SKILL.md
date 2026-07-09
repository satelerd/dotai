---
name: db-sqlserver-local
description: Guia para conectarse a SQL Server RDS desde desarrollo local usando kubectl port-forward y tunnel de Kubernetes
argument-hint: [python|nodejs|dotnet|dbeaver|docker|troubleshooting]
---

# Conexion a SQL Server RDS - Desarrollo Local

Guia completa para conectarse a la base de datos SQL Server (RDS) desde desarrollo local.

## Arquitectura del Tunnel

El archivo `db-tunnel.yaml` crea un pod en Kubernetes que actua como proxy TCP hacia la base de datos:

```
[Tu maquina local] --> [kubectl port-forward] --> [Pod db-tunnel] --> [SQL Server RDS]
```

El pod usa `alpine/socat` para redirigir el trafico del puerto 1433 hacia el host de la BD almacenado en un Secret.

---

## REGLAS DE USO (OBLIGATORIO)

**PERMISOS:**
- **SELECT**: Permitido
- **INSERT/UPDATE**: Permitido, pero SIEMPRE preguntar al usuario antes de ejecutar. NUNCA auto-aceptar ediciones.
- **DELETE**: PROHIBIDO. NUNCA ejecutar DELETE bajo ninguna circunstancia.

**ANTES DE CUALQUIER MODIFICACION:**
1. Mostrar el query exacto que se va a ejecutar
2. Esperar confirmacion explicita del usuario
3. NUNCA asumir que el usuario quiere modificar datos

---

## Credenciales

| Campo | Valor |
|-------|-------|
| **Host RDS** | `smartup-web-eks.cmlicgyso6h5.us-east-1.rds.amazonaws.com` |
| **Puerto** | `1433` |
| **Usuario** | `admin` |
| **Password** | `nbwHQGWfJhgllP7bWXrQ` |

### Bases de Datos Disponibles

| Base de Datos | Descripcion |
|---------------|-------------|
| `smart_orders_v3` | SmartOrders produccion |
| `SmartVOC_v3` | SmartVOC produccion |
| `database_agente001_dev_v3` | Agente 001 desarrollo |

### Connection Strings Listos para Usar

```bash
# sqlcmd (linea de comandos)
sqlcmd -S localhost,1433 -U admin -P 'nbwHQGWfJhgllP7bWXrQ' -d smart_orders_v3

# SQLAlchemy (Python)
mssql+pyodbc://admin:nbwHQGWfJhgllP7bWXrQ@localhost:1433/smart_orders_v3?driver=ODBC+Driver+18+for+SQL+Server&encrypt=yes&trustServerCertificate=yes

# JDBC (DBeaver)
jdbc:sqlserver://localhost:1433;databaseName=smart_orders_v3;user=admin;password=nbwHQGWfJhgllP7bWXrQ;encrypt=true;trustServerCertificate=true
```

---

## Desplegar el Pod del Tunnel

```bash
# Aplicar el manifiesto
kubectl apply -f db-tunnel.yaml

# Verificar que el pod este corriendo
kubectl get pods -n smartup -l app=db-tunnel

# Ver logs del tunnel
kubectl logs -n smartup db-tunnel
```

---

## Port-Forward a tu Maquina Local

Una vez el pod este corriendo, puedes hacer port-forward:

```bash
# Port-forward basico (puerto 1433 local -> 1433 del pod)
kubectl port-forward -n smartup pod/db-tunnel 1433:1433

# Port-forward con puerto local diferente (ej: 14330)
kubectl port-forward -n smartup pod/db-tunnel 14330:1433

# Port-forward en background
kubectl port-forward -n smartup pod/db-tunnel 1433:1433 &
```

**Nota**: El port-forward debe mantenerse activo mientras necesites la conexion. Si se cierra, la conexion a la BD se pierde.

---

## Connection Strings

### Para aplicaciones locales (fuera de Docker)

| Tipo | Connection String |
|------|-------------------|
| **Python (pyodbc)** | `Driver={ODBC Driver 18 for SQL Server};Server=localhost,1433;Database=smartvoc;Uid=tu_usuario;Pwd=tu_password;Encrypt=yes;TrustServerCertificate=yes;` |
| **Python (pymssql)** | `mssql+pymssql://tu_usuario:tu_password@localhost:1433/smartvoc` |
| **SQLAlchemy** | `mssql+pyodbc://tu_usuario:tu_password@localhost:1433/smartvoc?driver=ODBC+Driver+18+for+SQL+Server&encrypt=yes&trustServerCertificate=yes` |
| **Node.js (mssql)** | `Server=localhost,1433;Database=smartvoc;User Id=tu_usuario;Password=tu_password;Encrypt=true;TrustServerCertificate=true;` |
| **.NET** | `Server=localhost,1433;Database=smartvoc;User Id=tu_usuario;Password=tu_password;Encrypt=True;TrustServerCertificate=True;` |

### Para aplicaciones en Docker (en la misma red)

Cuando tu app corre en Docker, `localhost` no funciona. Usa `host.docker.internal`:

| Tipo | Connection String |
|------|-------------------|
| **Python (pyodbc)** | `Driver={ODBC Driver 18 for SQL Server};Server=host.docker.internal,1433;Database=smartvoc;Uid=tu_usuario;Pwd=tu_password;Encrypt=yes;TrustServerCertificate=yes;` |
| **SQLAlchemy** | `mssql+pyodbc://tu_usuario:tu_password@host.docker.internal:1433/smartvoc?driver=ODBC+Driver+18+for+SQL+Server&encrypt=yes&trustServerCertificate=yes` |
| **Node.js** | `Server=host.docker.internal,1433;Database=smartvoc;User Id=tu_usuario;Password=tu_password;Encrypt=true;` |

**Importante para Docker Desktop**: `host.docker.internal` resuelve a la IP de tu maquina host. En Linux sin Docker Desktop, puede que necesites usar la IP de tu maquina o configurar `--add-host`.

---

## Configuracion en DBeaver

### Descargar DBeaver

1. Ve a [https://dbeaver.io/download/](https://dbeaver.io/download/)
2. Descarga la version Community (gratuita) para tu sistema operativo
3. Instala siguiendo el wizard

### Crear Nueva Conexion

1. Click en **Database** > **New Database Connection**
2. Selecciona **SQL Server**
3. Click en **Next**

### Configuracion de Conexion

#### Opcion 1: Configuracion por campos

| Campo | Valor |
|-------|-------|
| **Host** | `localhost` |
| **Port** | `1433` (o el puerto que usaste en port-forward) |
| **Database** | `smartvoc` |
| **Authentication** | SQL Server Authentication |
| **Username** | `tu_usuario` |
| **Password** | `tu_password` |

En la pestana **Driver properties**:
- `encrypt` = `true`
- `trustServerCertificate` = `true`

#### Opcion 2: JDBC URL Manual

Click en **Edit Driver Settings** o usa la pestana **URL** y pega:

```
jdbc:sqlserver://localhost:1433;databaseName=smartvoc;encrypt=true;trustServerCertificate=true
```

### Test de Conexion

1. Asegurate de que el port-forward este activo
2. En DBeaver, click en **Test Connection**
3. Si pide descargar drivers, acepta
4. Deberia mostrar "Connected"

### Mostrar todas las Bases de Datos

Por defecto DBeaver solo muestra la BD especificada en la conexion. Para ver todas las BDs del servidor:

1. Click derecho en la conexion > **Edit Connection**
2. Ve a la pestana **Connection settings** (o **General**)
3. Busca la opcion **"Show all databases"** o **"Show all schemas"**
4. Activa el checkbox
5. Click en **OK**
6. Click derecho en la conexion > **Refresh**

---

## JDBC URLs para diferentes escenarios

```
# Conexion basica
jdbc:sqlserver://localhost:1433;databaseName=smartvoc

# Con encriptacion (recomendado)
jdbc:sqlserver://localhost:1433;databaseName=smartvoc;encrypt=true;trustServerCertificate=true

# Puerto personalizado (Ej: 4500)
jdbc:sqlserver://localhost:4500;databaseName=smartvoc;encrypt=true;trustServerCertificate=true

# Conexion desde Docker a host
jdbc:sqlserver://host.docker.internal:1433;databaseName=smartvoc;encrypt=true;trustServerCertificate=true

# Con timeout de conexion
jdbc:sqlserver://localhost:1433;databaseName=smartvoc;encrypt=true;trustServerCertificate=true;loginTimeout=30

# Especificando instancia (si aplica)
jdbc:sqlserver://localhost:1433;instanceName=SQLEXPRESS;databaseName=smartvoc
```

---

## Troubleshooting

### Error: Connection refused

```bash
# Verifica que el pod este corriendo
kubectl get pods -n smartup -l app=db-tunnel

# Verifica que el port-forward este activo
ps aux | grep port-forward

# Reinicia el port-forward
kubectl port-forward -n smartup pod/db-tunnel 1433:1433
```

### Error: Login failed

- Verifica usuario y password
- Asegurate de que el usuario tenga permisos en la BD

### Error: Certificate validation failed

Agrega estos parametros a tu connection string:
- `TrustServerCertificate=true` (para drivers ODBC/.NET)
- `trustServerCertificate=true` (para JDBC)

### El port-forward se desconecta frecuentemente

```bash
# Usa un loop para reconectar automaticamente
while true; do kubectl port-forward -n smartup pod/db-tunnel 1433:1433; sleep 1; done
```

### No puedo conectar desde Docker

1. Asegurate de usar `host.docker.internal` en vez de `localhost`
2. Verifica que el port-forward este con `--address 0.0.0.0`:
   ```bash
   kubectl port-forward -n smartup pod/db-tunnel 1433:1433 --address 0.0.0.0
   ```

---

## Comandos Utiles

```bash
# Ver estado del pod
kubectl describe pod -n smartup db-tunnel

# Ver logs en tiempo real
kubectl logs -n smartup db-tunnel -f

# Reiniciar el pod
kubectl delete pod -n smartup db-tunnel
kubectl apply -f db-tunnel.yaml

# Verificar el secret
kubectl get secret -n smartup db-tunnel-secret -o yaml

# Test de conexion rapido con sqlcmd (si esta instalado)
sqlcmd -S localhost,1433 -U tu_usuario -P tu_password -d smartvoc -Q "SELECT 1"
```

---

## Variables de Entorno

### Formato del connection string (SQLAlchemy + ODBC 18)

```
mssql+pyodbc://<usuario>:<password>@<host>:<puerto>/<database>?driver=ODBC+Driver+18+for+SQL+Server&encrypt=yes&trustServerCertificate=yes
```

### Ejemplos para diferentes entornos (DB SmartVOC_v3)

```env
# Desarrollo local (con port-forward activo)
DB_SMARTVOC=mssql+pyodbc://user:tu_password@localhost:1433/SmartVOC_v3?driver=ODBC+Driver+18+for+SQL+Server&encrypt=yes&trustServerCertificate=yes

# Desarrollo con Docker (app dockerizada)
DB_SMARTVOC=mssql+pyodbc://user:tu_password@host.docker.internal:1433/SmartVOC_v3?driver=ODBC+Driver+18+for+SQL+Server&encrypt=yes&trustServerCertificate=yes
```

### JDBC para DBeaver (SmartVOC)

```
# SmartVOC_v3
jdbc:sqlserver://localhost:1433;databaseName=SmartVOC_v3;encrypt=true;trustServerCertificate=true;user=XXXXX;password=*****

# database_agente001_dev_v3
jdbc:sqlserver://localhost:1433;databaseName=database_agente001_dev_v3;encrypt=true;trustServerCertificate=true;user=XXXXXX;password=*****
```

---

## Script start.sh para Docker Compose

Para simplificar el desarrollo local, existe un script que automatiza el port-forward y levanta los servicios de Docker.

### Codigo del Script

```bash
#!/bin/bash

# Iniciar port-forward en background si el puerto no esta en uso
if ! lsof -i :1433 > /dev/null 2>&1; then
    echo "Iniciando port-forward a db-tunnel..."
    kubectl port-forward -n smartup pod/db-tunnel 1433:1433 &
    sleep 2
else
    echo "Puerto 1433 ya esta en uso, omitiendo port-forward..."
fi

# Levantar docker-compose
echo "Levantando docker-compose..."
docker compose up "$@"
```

### Uso

```bash
# Dar permisos de ejecucion (solo la primera vez)
chmod +x start.sh

# Levantar servicios (incluye port-forward automatico)
./start.sh

# Levantar en modo detached (background)
./start.sh -d

# Levantar con rebuild de imagenes
./start.sh --build

# Combinado
./start.sh -d --build
```

### Que hace el script?

1. **Verifica el puerto 1433**: Si ya esta en uso (porque ya hay un port-forward activo), lo omite
2. **Inicia port-forward**: Si el puerto esta libre, ejecuta `kubectl port-forward` en background
3. **Levanta Docker Compose**: Ejecuta `docker compose up` con los argumentos que le pases

### Notas importantes

- El script requiere tener `kubectl` configurado y acceso al cluster de Kubernetes
- El pod `db-tunnel` debe estar corriendo en el namespace `smartup`
- Si cierras el terminal, el port-forward se cerrara. Usa `./start.sh -d` para modo detached

---

## Resumen Rapido

| Escenario | Host a usar |
|-----------|-------------|
| App local + port-forward | `localhost` |
| App en Docker + port-forward | `host.docker.internal` |
