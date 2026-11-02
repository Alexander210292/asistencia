# Despliegue académico en AWS con OpenTofu

Esta guía despliega la aplicación existente en dos instancias EC2. Ejecuta los comandos desde la raíz del repositorio, salvo que se indique que corresponden a PowerShell local, la instancia backend o la instancia frontend.

## Arquitectura

```text
Navegador
  | HTTP :8080
  v
EC2 frontend (Ubuntu 24.04, Node.js 22)
  | El JavaScript del navegador llama directamente a la API
  | HTTP :3000
  v
EC2 backend (Ubuntu 24.04, Node.js 22 + Express + MySQL)
  | MySQL escucha localmente en 127.0.0.1:3306
```

La plantilla alternativa de CloudFormation está en [`CloudFormation/asistencia.yaml`](./CloudFormation/asistencia.yaml). CloudFormation administra los recursos mediante un stack y no necesita un archivo de estado local ni el backend S3 de OpenTofu. Usa CloudFormation **o** OpenTofu para esta infraestructura; no despliegues ambos sobre los mismos recursos.

## Despliegue alternativo con CloudFormation

Este template crea la misma arquitectura de red y EC2: VPC `10.24.0.0/16`, una subred pública `/24`, Internet Gateway y ruta pública, grupos de seguridad, y dos instancias Ubuntu 24.04 con volúmenes gp3 cifrados de 12 GiB. No configura MySQL, Node.js, la aplicación ni sus servicios, igual que el módulo OpenTofu actual. La regla API usa el CIDR indicado, SSH se restringe al CIDR del operador y no existe regla entrante para MySQL.

CloudFormation no comparte las llaves privadas que crea una plantilla. Crea primero un key pair EC2 en la consola de AWS o con AWS CLI, guarda el `.pem` de forma segura y pasa únicamente el nombre del key pair como parámetro. Define también el CIDR público de tu operador para SSH, por ejemplo `203.0.113.10/32`.

Ejemplo con AWS CLI desde PowerShell (ajusta perfil, región y CIDR):

```powershell
Set-Location "F:\Diplomado\Mod2\asistencia\infra\aws"
$env:AWS_PROFILE = "asistencia-equipo"
$region = "us-east-2"
$sshCidr = "TU_IPV4_PUBLICA/32"
$keyPairName = "asistencia-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
aws sts get-caller-identity
aws ec2 create-key-pair --key-name $keyPairName --key-type rsa --query KeyMaterial --output text --region $region | Out-File -Encoding ascii -NoClobber .\asistencia-aws.pem
icacls .\asistencia-aws.pem /inheritance:r /grant:r "$($env:USERNAME):(R)"
aws cloudformation validate-template --template-body file://CloudFormation/asistencia.yaml --region $region
aws cloudformation deploy --template-file CloudFormation/asistencia.yaml --stack-name uagrm-asistencia-academic-demo --region $region --parameter-overrides KeyPairName=$keyPairName SshIngressCidr=$sshCidr ApiIngressCidr=0.0.0.0/0 InstanceType=t3.micro
aws cloudformation describe-stacks --stack-name uagrm-asistencia-academic-demo --region $region --query "Stacks[0].Outputs" --output table
```

Protege el `.pem`: el comando de creación devuelve la clave privada una sola vez y `-NoClobber` evita sobrescribir un archivo existente. Si ya tienes un key pair utilizable, omite `create-key-pair` y define `$keyPairName` con ese nombre. El template usa el parámetro público de SSM de Canonical para resolver la AMI vigente de Ubuntu 24.04 en la región elegida. Considera el costo de instancias, discos y direcciones IPv4 públicas, y elimina el stack al terminar la práctica:

```powershell
aws cloudformation delete-stack --stack-name uagrm-asistencia-academic-demo --region $region
aws cloudformation wait stack-delete-complete --stack-name uagrm-asistencia-academic-demo --region $region
aws ec2 delete-key-pair --key-name $keyPairName --region $region
```

Ambas instancias están en una subred pública IPv4 de la misma VPC. El grupo de seguridad frontend permite HTTP en 8080 y SSH en 22 desde la IP del operador. El grupo backend permite la API en 3000 desde el CIDR configurado y SSH desde la IP del operador. No hay regla entrante para MySQL 3306. CORS autoriza el origen del navegador, pero no sustituye el firewall.

Es un entorno de pruebas: la aplicación se sirve por HTTP, sin dominio, TLS/HTTPS, balanceador, respaldos ni alta disponibilidad. No se deben usar datos personales reales.

## Archivos de infraestructura

| Archivo | Función |
|---|---|
| `main.tf` | Declara OpenTofu y los proveedores AWS, TLS y Local. Crea VPC, subred IPv4, Internet Gateway, rutas, llave SSH, security groups y las dos instancias EC2 Ubuntu. |
| `variables.tf` | Define región, tipo de instancia y rangos CIDR configurables. Las credenciales las obtiene el proveedor del perfil AWS local. |
| `outputs.tf` | Imprime URLs, comandos SSH, IP privada del backend y ruta local de la llave PEM. |
| `backend.tf` | Declara el backend S3; la configuración de bucket y clave se suministra desde el archivo local ignorado `backend.hcl`. |
| `backend.hcl.example` | Plantilla sin credenciales para apuntar al bucket de estado compartido. Cada operador la copia a `backend.hcl` y completa el nombre del bucket y la región. |
| `state-bootstrap/` | Crea el bucket S3 de estado con acceso público bloqueado, cifrado, versionado y política que exige HTTPS. Su estado también se migra al mismo bucket. `backend.tf.example` se copia a `backend.tf` tras crear el bucket. |
| `.terraform.lock.hcl` | Fija las versiones de proveedores seleccionadas por `tofu init`; se conserva en el repositorio. |
| `terraform.tfvars` | Variables locales de despliegue (por ejemplo, CIDR y tipo de instancia). Está excluido de Git. No contiene credenciales AWS. |
| `asistencia-aws.pem` | Llave privada SSH generada localmente para conectarse a ambas EC2. Está excluida de Git. |
| `terraform.tfstate` | Antes de la migración, estado local existente. Después, el estado activo se mantiene en S3; contiene información sensible, incluida la llave privada generada. |
| `../../.gitignore` | Archivo de exclusiones ubicado en la raíz del repositorio; omite `.terraform`, estado, planes, variables locales y llaves PEM. |

La configuración solo usa IPv4. Las direcciones públicas de EC2 pueden cambiar si se detienen y vuelven a iniciar las instancias.

## Costos y requisitos de AWS

Las cuentas nuevas de AWS usan créditos y un plan de duración limitada; el costo y la elegibilidad dependen de la cuenta, la región y el plan. Dos instancias, discos, transferencia de datos y dos IPv4 públicas pueden consumir créditos o generar cargos. Revisa **Billing** antes de aplicar y configura alertas. `tofu plan` no es un estimador de costos.

Necesitas OpenTofu 1.10 o superior, AWS CLI, PowerShell con OpenSSH y una cuenta AWS que permita crear el bucket S3, la política, versionado y recursos EC2/VPC. Usa una identidad no-root distinta para cada persona, preferiblemente AWS IAM Identity Center (SSO). Cada identidad debe tener permisos para los recursos de AWS que administra, además de leer y actualizar el objeto de estado y crear/eliminar el archivo de bloqueo S3. No compartas claves de acceso entre usuarios.

Configura un perfil personal de AWS CLI siguiendo las instrucciones de tu administrador. Para IAM Identity Center, una vez configurado el perfil:

```powershell
aws sso login --profile TU_PERFIL
$env:AWS_PROFILE = "TU_PERFIL"
aws sts get-caller-identity
```

Para una práctica académica sin IAM Identity Center, el administrador puede crear un usuario IAM distinto por integrante, asignarle solo los permisos necesarios y generar para cada uno una access key para uso programático. Cada integrante configura su propia máquina una sola vez:

```powershell
aws configure --profile asistencia-equipo
# Ingresar la access key y el secret access key propios de ese usuario.
# Región: us-east-2
$env:AWS_PROFILE = "asistencia-equipo"
aws sts get-caller-identity
```

La última orden debe mostrar la cuenta y el usuario IAM esperado. La contraseña para iniciar sesión en la consola web no sirve como credencial de AWS CLI: cada usuario debe configurar su propia access key o usar SSO. No compartas una misma access key entre integrantes; si el secret se pierde, crea otra y revoca la anterior. No envíes credenciales por chat ni las guardes en el repositorio.

El perfil de AWS CLI se guarda en los archivos de configuración locales del usuario y lo usan tanto OpenTofu como el backend S3. `terraform.tfvars` es para variables de la infraestructura, no es el mecanismo de autenticación del backend: `tofu init` accede al bucket antes de cargar esas variables. Por eso introducir las claves en `terraform.tfvars` no resuelve un error de autenticación al inicializar el backend. Tampoco pongas claves en `backend.hcl`.

Cada integrante necesita permisos AWS para operar los recursos de la práctica y para acceder al bucket. Para el estado compartido requiere `s3:ListBucket` en el bucket, lectura/escritura sobre los objetos de estado y lectura/escritura/borrado sobre los archivos `.tflock`; el creador del bootstrap necesita además permisos para crear y configurar el bucket. Otorga estos permisos mediante una política IAM a los usuarios o grupos del equipo. El bloqueo serializa los cambios del mismo estado, pero no reemplaza los permisos individuales. Si la cuenta pertenece a AWS Organizations y una SCP deniega acciones EC2 o S3, un administrador de la organización debe autorizar la práctica.

Si `aws sts get-caller-identity` falla, primero corrige el perfil o la access key de AWS CLI; si funciona pero `tofu init` devuelve `AccessDenied`, la identidad sí se autenticó, pero le faltan permisos IAM para el bucket o la clave de estado.

## Backend S3 compartido y bloqueo de concurrencia

El estado y el lockfile son compartidos entre quienes configuren el mismo bucket, región y clave. OpenTofu 1.10+ usa el bloqueo nativo de S3 (`use_lockfile = true`): el primer `apply` que adquiere el bloqueo continúa; otros `apply` al mismo estado esperan a que se libere. No se usa DynamoDB. El versionado de objetos permite recuperar versiones anteriores del estado, y el cifrado SSE-S3 protege los objetos en reposo.

El bucket tiene nombre globalmente único y se crea una sola vez con el módulo `state-bootstrap`. Acordad un nombre estable con el equipo; no uséis un bucket diferente por operador. El bucket está separado de la infraestructura de la aplicación y `force_destroy = false` evita eliminarlo accidentalmente mientras contenga estado. A cada operador hay que concederle `s3:ListBucket` sobre el bucket, `s3:GetObject`/`s3:PutObject` sobre cada clave de estado y `s3:GetObject`/`s3:PutObject`/`s3:DeleteObject` sobre las claves `.tflock` correspondientes. Quien crea el bootstrap necesita además permisos para crear el bucket y configurar bloqueo de acceso público, propiedad, cifrado, versionado y política.

### Crear el bucket y migrar los estados locales

Primero inicia sesión con la identidad AWS que administrará el bootstrap. Desde PowerShell, sustituye `uagrm-asistencia-tofu-123456789012-a1b2c3` por un nombre globalmente único en minúsculas. `state_bucket_name` no debe cambiar después:

```powershell
$env:AWS_PROFILE = "TU_PERFIL"
aws sts get-caller-identity
cd "F:\Diplomado\Mod2\asistencia\infra\aws\state-bootstrap"
@'
aws_region       = "us-east-2"
state_bucket_name = "uagrm-asistencia-tofu-123456789012-a1b2c3"
'@ | Set-Content .\terraform.tfvars
tofu init
tofu fmt -check
tofu validate
tofu plan
tofu apply
```

Este primer `apply` crea el bucket usando temporalmente estado local. En cuanto termine, configura el backend del propio bootstrap y migra su estado al bucket:

```powershell
Copy-Item .\backend.hcl.example .\backend.hcl
```

Edita `backend.hcl` para reemplazar el marcador por el mismo nombre de bucket y poner la región elegida. Activa el backend remoto del bootstrap y migra el estado local recién creado:

```powershell
Copy-Item .\backend.tf.example .\backend.tf
tofu init -migrate-state -backend-config=backend.hcl
tofu state list
```

Vuelve al módulo de infraestructura principal y migra el estado local existente de `infra/aws` (incluidos los recursos ya desplegados):

```powershell
cd "F:\Diplomado\Mod2\asistencia\infra\aws"
Copy-Item .\backend.hcl.example .\backend.hcl
```

Edita el archivo local `backend.hcl` con el mismo bucket y región, sin cambiar la clave `uagrm-asistencia/infra/terraform.tfstate`. Luego migra e inspecciona:

```powershell
tofu init -migrate-state -backend-config=backend.hcl
tofu state list
tofu plan
```

La migración copia el estado activo `terraform.tfstate`; no selecciona automáticamente `terraform.tfstate.backup`. Antes de migrar, compara `tofu state list` con el backup y con los recursos que realmente existen en AWS. Si el estado activo no contiene recursos y el backup sí, detente: no migres ni apliques hasta confirmar si esos recursos aún existen y cuál estado es autoritativo. No restaures un backup solo por tener más recursos; un estado obsoleto puede causar modificaciones o eliminaciones equivocadas.

Detente si `tofu init` propone borrar o reemplazar recursos, si falta el estado esperado o si el plan no es el esperado. No ejecutes `tofu apply` hasta revisar el estado migrado. No compartas ni borres los archivos locales de estado o backup hasta verificar en AWS que ambos estados estén en el bucket y el plan principal conserve los recursos actuales. Después de confirmar la migración, protege y elimina las copias locales antiguas siguiendo las reglas de tu equipo.

### Incorporar a otros operadores

Cada persona configura su propio perfil AWS con los permisos necesarios, copia el ejemplo y coloca el mismo nombre de bucket/región:

```powershell
cd "F:\Diplomado\Mod2\asistencia\infra\aws"
Copy-Item .\backend.hcl.example .\backend.hcl
tofu init -backend-config=backend.hcl
tofu plan
```

En `infra/aws/state-bootstrap`, las personas que necesiten inspeccionar el bootstrap también copian `backend.tf.example` a `backend.tf` y `backend.hcl.example` a `backend.hcl`, completan bucket/región y ejecutan `tofu init -backend-config=backend.hcl`. No vuelvan a ejecutar el primer `tofu init` local ni creen otro bucket.

`backend.hcl` solo contiene identificador de bucket, clave y región; está excluido de Git. Comparte esos valores no secretos por el canal del equipo o acuerda un nombre fijo documentado. Nunca copies `terraform.tfstate`, `terraform.tfstate.backup`, `.terraform` o credenciales AWS entre equipos.

Para permitir esperar hasta diez minutos por el bloqueo:

```powershell
tofu apply -lock-timeout=10m
```

No uses `-lock=false`. Si una ejecución falla, espera a confirmar que ya no hay ningún `plan` o `apply` activo antes de usar `tofu force-unlock`; retirar un bloqueo vigente puede permitir escrituras simultáneas y corromper el estado. Los bloqueos se liberan automáticamente al terminar normalmente el `apply`.

## Preparar variables

Obtén la IPv4 pública actual de tu red de administración desde PowerShell:

```powershell
(curl.exe -4 -s https://checkip.amazonaws.com).Trim()
```

Agrega `/32` al resultado para permitir SSH solo desde esa dirección. Crea `infra/aws/terraform.tfvars` localmente, sustituyendo todos los marcadores:

```hcl
aws_region       = "us-east-1"
instance_type    = "t3.micro"
ssh_ingress_cidr = "TU_IPV4_PUBLICA/32"
api_ingress_cidr = "0.0.0.0/0"
```

`api_ingress_cidr = "0.0.0.0/0"` deja el API accesible desde cualquier IPv4, necesario si los estudiantes usarán redes distintas. Para una demostración privada, limita ese rango a las IP cliente conocidas. No abras el puerto 3306.

## Inicializar y revisar el plan

Desde PowerShell, en la raíz del repositorio:

```powershell
cd "F:\Diplomado\Mod2\asistencia\infra\aws"
tofu init -backend-config=backend.hcl
tofu fmt -check
tofu validate
tofu plan
```

El plan esperado incluye dos EC2 y recursos de red, security groups y llave. Léelo con atención. `tofu plan` no crea recursos ni confirma que el costo sea cero. Cuando hayas revisado permisos y costos en Billing, crea la infraestructura:

```powershell
tofu apply
tofu output
```

Confirma el plan escribiendo `yes`. Guarda las salidas `frontend_url`, `backend_api_url`, `frontend_ssh` y `backend_ssh`; las IP de ejemplo de esta guía no son permanentes. Limita el ACL de la llave PEM en Windows:

```powershell
cd "F:\Diplomado\Mod2\asistencia\infra\aws"
icacls .\asistencia-aws.pem /inheritance:r /grant:r "$($env:USERNAME):(R)"
```

No compartas el `.pem` ni el archivo de estado.

## Preparar el backend

Usa la IP pública actual de `backend_ssh` y conéctate desde PowerShell:

```powershell
ssh -i .\asistencia-aws.pem ubuntu@IP_PUBLICA_BACKEND
```

En Ubuntu instala MySQL y Node.js 22:

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg mysql-server
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
sudo systemctl enable --now mysql
node --version
npm --version
```

Crea la base y el usuario MySQL local. Usa una contraseña aleatoria nueva; no reutilices claves locales ni la de administrador. Desde SSH:

```bash
sudo mysql
```

En el prompt `mysql>`, sustituye `CLAVE_MYSQL_NUEVA` por la misma contraseña aleatoria en todos los lugares:

```sql
CREATE DATABASE IF NOT EXISTS uagrm_asistencia CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'asistencia_app'@'localhost' IDENTIFIED BY 'CLAVE_MYSQL_NUEVA';
ALTER USER 'asistencia_app'@'localhost' IDENTIFIED BY 'CLAVE_MYSQL_NUEVA';
CREATE USER IF NOT EXISTS 'asistencia_app'@'127.0.0.1' IDENTIFIED BY 'CLAVE_MYSQL_NUEVA';
ALTER USER 'asistencia_app'@'127.0.0.1' IDENTIFIED BY 'CLAVE_MYSQL_NUEVA';
GRANT ALL PRIVILEGES ON uagrm_asistencia.* TO 'asistencia_app'@'localhost';
GRANT ALL PRIVILEGES ON uagrm_asistencia.* TO 'asistencia_app'@'127.0.0.1';
GRANT CREATE ON *.* TO 'asistencia_app'@'localhost';
GRANT CREATE ON *.* TO 'asistencia_app'@'127.0.0.1';
FLUSH PRIVILEGES;
EXIT;
```

El permiso global `CREATE` permite que el script de instalación ejecute `CREATE DATABASE IF NOT EXISTS`; se revoca después de la inicialización.

En otra ventana de PowerShell local, desde la raíz del repositorio, copia el código backend. Sustituye la IP por la salida vigente de `backend_ssh`:

```powershell
cd "F:\Diplomado\Mod2\asistencia"
ssh -i .\infra\aws\asistencia-aws.pem ubuntu@IP_PUBLICA_BACKEND "mkdir -p ~/asistencia-backend"
scp -i .\infra\aws\asistencia-aws.pem -r .\package.json .\package-lock.json .\src .\scripts .\database ubuntu@IP_PUBLICA_BACKEND:~/asistencia-backend/
```

Vuelve a la sesión SSH del backend y prepara dependencias y entorno:

```bash
cd ~/asistencia-backend
npm ci --omit=dev
nano .env.backend
```

El archivo remoto debe contener los siguientes valores. Usa el origen exacto mostrado por `frontend_url`; `DB_PASSWORD` debe coincidir con la clave de MySQL; crea una clave admin nueva de al menos 12 caracteres:

```dotenv
BACKEND_HOST=0.0.0.0
PORT=3000
FRONTEND_ORIGINS=http://IP_PUBLICA_FRONTEND:8080
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=asistencia_app
DB_PASSWORD=CLAVE_MYSQL_NUEVA
DB_NAME=uagrm_asistencia
ADMIN_USER=admin
ADMIN_PASSWORD=CLAVE_ADMIN_NUEVA_DE_12_CARACTERES_O_MAS
INSTITUTION_TIMEZONE=America/La_Paz
```

Guarda en nano con `Ctrl+O`, `Enter`, `Ctrl+X`; protege el archivo e inicializa:

```bash
chmod 600 .env.backend
npm run db:init
```

Debe aparecer `Base de datos lista`. El primer `db:init` crea al administrador con la clave de entorno. Si el administrador ya existe, el script conserva su hash; cambiar `ADMIN_PASSWORD` no lo actualiza. Revoca el permiso temporal y configura un servicio persistente:

```bash
sudo mysql -e "REVOKE CREATE ON *.* FROM 'asistencia_app'@'localhost'; REVOKE CREATE ON *.* FROM 'asistencia_app'@'127.0.0.1'; FLUSH PRIVILEGES;"
sudo tee /etc/systemd/system/asistencia-backend.service >/dev/null <<'EOF'
[Unit]
Description=API de Control de Asistencia
After=network.target mysql.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/asistencia-backend
ExecStart=/usr/bin/npm run start:backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now asistencia-backend
sudo systemctl status asistencia-backend --no-pager
```

Para ver logs: `sudo journalctl -u asistencia-backend -f`.

## Preparar el frontend

En PowerShell local, copia los archivos a la instancia frontend usando su IP pública actual:

```powershell
cd "F:\Diplomado\Mod2\asistencia"
ssh -i .\infra\aws\asistencia-aws.pem ubuntu@IP_PUBLICA_FRONTEND "mkdir -p ~/asistencia-frontend/frontend"
scp -i .\infra\aws\asistencia-aws.pem .\package.json ubuntu@IP_PUBLICA_FRONTEND:~/asistencia-frontend/
scp -i .\infra\aws\asistencia-aws.pem .\frontend\server.js ubuntu@IP_PUBLICA_FRONTEND:~/asistencia-frontend/frontend/
scp -i .\infra\aws\asistencia-aws.pem -r .\public ubuntu@IP_PUBLICA_FRONTEND:~/asistencia-frontend/
```

Conéctate al frontend y, si aún no está instalado, prepara Node.js 22:

```powershell
ssh -i .\infra\aws\asistencia-aws.pem ubuntu@IP_PUBLICA_FRONTEND
```

```bash
sudo apt update
sudo apt install -y ca-certificates curl
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
node --version
```

Crea su configuración pública, sustituyendo la IP backend:

```bash
cd ~/asistencia-frontend
cat > .env.frontend <<'EOF'
FRONTEND_HOST=0.0.0.0
FRONTEND_PORT=8080
API_BASE_URL=http://IP_PUBLICA_BACKEND:3000
EOF
chmod 600 .env.frontend
```

El frontend solo usa APIs incluidas en Node.js, así que no necesita `npm ci`. Configura un servicio persistente:

```bash
sudo tee /etc/systemd/system/asistencia-frontend.service >/dev/null <<'EOF'
[Unit]
Description=Cliente web de Control de Asistencia
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/asistencia-frontend
ExecStart=/usr/bin/npm run start:frontend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now asistencia-frontend
sudo systemctl status asistencia-frontend --no-pager
```

Los logs se consultan con `sudo journalctl -u asistencia-frontend -f`.

## Verificar el despliegue

Abre `frontend_url` en el navegador. El backend debe estar activo y su `FRONTEND_ORIGINS` debe coincidir exactamente con el origen del navegador, incluido protocolo y puerto. Desde PowerShell puedes comprobar el preflight CORS:

```powershell
curl.exe -i -X OPTIONS "http://IP_PUBLICA_BACKEND:3000/api/login" -H "Origin: http://IP_PUBLICA_FRONTEND:8080" -H "Access-Control-Request-Method: POST"
```

La respuesta esperada es `204 No Content` y `Access-Control-Allow-Origin` con el origen del frontend. Ingresa como `admin` con la clave creada en el backend, crea el módulo e importa estudiantes y fechas para habilitar el acceso de estudiantes.

Si aparece CORS 403, revisa `FRONTEND_ORIGINS` en el archivo remoto del backend y reinicia el servicio con `sudo systemctl restart asistencia-backend`. Si no carga la página, revisa `sudo systemctl status asistencia-frontend` y que el grupo de seguridad permita 8080. Para MySQL, revisa `sudo systemctl status mysql` y las variables del `.env.backend` remoto. Nunca pegues archivos `.env`, contraseñas, claves IAM o llaves PEM en chats o repositorios.

## Detener y eliminar

Detener una EC2 no equivale a borrar todos los recursos asociados ni elimina los costos de discos/IP. Al terminar la práctica, desde `infra/aws` revisa y confirma:

```powershell
tofu plan -destroy
tofu destroy
```

Esto elimina las instancias y la red administradas por este módulo, además de borrar la llave PEM local administrada por OpenTofu. No elimina el bucket ni los estados, que pertenecen al módulo separado `state-bootstrap`; conserva el bucket mientras el equipo necesite el estado. No vacíes ni elimines el bucket como parte del `tofu destroy` de la aplicación. Verifica Billing para confirmar que no queden recursos facturables.
