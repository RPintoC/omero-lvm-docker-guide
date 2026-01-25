# Guía para la instalacion y configuracion de Omero-Server y Omero-Web con Dockers y LVM

## Objetivo
- Desplegar OMERO Server + OMERO Web en un servidor local, con:
- Almacenamiento persistente mediante LVM dedicado
- PostgreSQL aislado (manejado por Docker)
- Acceso vía red local (LAN)
- Sin dependencia de:
  - dominio público
  - IP fija
  - acceso a internet externo

## Escenario de red asumido
- El servidor sólo es accesible dentro de la red local
- IP asignada por DHCP (IP puede cambiar)
- Los clientes acceden usando:
  - IP local actual del servidor
  - nombre local (editando /etc/hosts del lado del cliente)

## Requisitos
- Sistema
  - Ubuntu 24.04 LTS
  - Usuario con privilegios sudo
  - Acceso a terminal
- Almacenamiento
  - Un disco separado del sistema operativo (más discos en caso de querer expandir el espacio)
  - LVM disponible
- Conocimientos mínimos
  - Uso de la línea de comandos en Linux
    - Navegación básica (cd, ls)
    - Edición de archivos con editores de texto en terminal (por ejemplo, nano o vi)

## Cambiar a modo administrador (Usuario con privilegios sudo)
Ejecuta el comando sudo su para entrar en modo administrador.
```bash
sudo su
```
**En caso de no hacer esto deberás agregar _sudo_ al inicio de todos los comandos usados en esta guía.**

## Instalar LVM (en caso de no instalarlo junto al SO)
```bash
apt update
apt install -y lvm2
```

## Preparación del almacenamiento con LVM
### Verificar que se reconozca el disco secundario
```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```
o
```bash
lsblk -o NAME #para ver únicamente los nombres
```

En esta guía se asume que el nuevo disco es: /dev/sdb.

En caso de que el disco nuevo no sea sdb cambiar el nombre en las siguientes instrucciones.

El nombre del disco se puede averiguar si se ejecuta el comando antes y después de haber conectado el disco secundario y comparar los resultados del comando.
(Nota: en el escenario donde se instaló LVM en un SO preexistente la línea "_ubuntu - - vg - ubuntu - - lv_" no aparecerá, esto no afecta al proceso descrito en esta guía).

### Limpiar disco (opcional, destructivo, borra todo su contenido actual)
```bash
wipefs -a /dev/sdb
```
### Crear partición LVM
```bash
parted /dev/sdb --script mklabel gpt
parted /dev/sdb --script mkpart primary 0% 100%
parted /dev/sdb --script set 1 lvm on
```
### Crear volumen físico (PV)
```bash
pvcreate /dev/sdb1
```

### Crear grupo de volúmenes (VG) “omeroStorage”
```bash
vgcreate omeroStorage /dev/sdb1
```
### Crear volumen lógico (LV)
```bash
lvcreate -l 100%FREE -n omeroData omeroStorage
```

### Formatear volumen (LV)
```bash
mkfs.ext4 /dev/omeroStorage/omeroData
```

### Crear el punto de montaje
```bash
mkdir -p /omero/data
```

### Ubica el UUID
```bash
blkid /dev/omeroStorage/omeroData
```
Al ejecutar el comando se obtendrá una secuencia de alfanumérica que es el Identificador único universal (Universally unique identifier o UUID) (**debes preservar este dato ya que será necesario en el siguiente paso**) 

### Editar el archivo /etc/fstab
Puedes ejecutar el comando `nano /etc/fstab` para abrirlo y editarlo.
```bash
nano /etc/fstab
```
Copia y reemplaza `<EL_UUID_AQUI>` por el UUID que obtuviste previamente.
```bash
UUID=<EL_UUID_AQUI> /omero/data ext4 defaults 0 2
```
Agrega la línea de texto al archivo `/etc/fstab` y guarda los cambios.

### Montar el disco:
```bash
systemctl daemon-reload
mount -a
```

## Instalación de Docker
### Crear directorio para contener los archivos necesarios para Omero con Docker
```bash
mkdir -p ~/omero
cd ~/omero
```
### Agregar llaves GPG oficiales de Docker
```bash
apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1)
apt update
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
```

### Agregar fuentes de repositorio apt:
```bash
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb ➔ URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "$UBUNTU_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt update
```

### Instalar paquetes docker:
```bash
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Verificar la instalación de docker
```bash
systemctl status docker
```

### Imágenes Docker
```bash
docker pull postgres
docker pull openmicroscopy/omero-server
docker pull openmicroscopy/omero-web-standalone
```

## Preparando el entorno para usar Omero-Server y Omero-Web
### Asegurate de estar en el directorio ~/omero para generar los archivos necesarios para Omero con Docker
```bash
cd ~/omero
```

### Crear archivo “.env” para variables sensibles
```bash
nano .env
```

Contenido del archivo .env:
```bash
# --- Base de datos ---
OMERO_DB_USER=omero_db
OMERO_DB_PASS=CAMBIAR_PASSWORD
OMERO_DB_NAME=omero
# --- Servidor OMERO ---
OMERO_ROOT_PASS=CAMBIAR_ROOT_PASS
# --- Web ---
OMERO_WEB_PORT=8080:8080
```
Puedes y debes modificar el valor de estas variables a tu gusto.

### Crear docker-compose.yml
Puedes descargar el archivo de: https://github.com/RPintoC/omero-lvm-docker-guide/blob/main/docker-compose.yml

O puedes crearlo tu mismo:
```bash
nano docker-compose.yml
```

Contenido del archivo docker-compose.yml (la indentación debe recrearse exactamente como se ven en este documento para que funcione, la indentación la generas con la tecla Tab):
```bash
services:
  db:
    image: postgres:13
    container_name: omero-db
    restart: always
    env_file: .env
    environment:
      POSTGRES_USER: ${OMERO_DB_USER}
      POSTGRES_PASSWORD: ${OMERO_DB_PASS}
      POSTGRES_DB: ${OMERO_DB_NAME}
    volumes:
      - omero-db:/var/lib/postgresql/data
    shm_size: 1g
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${OMERO_DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - omero-net
  server:
    image: openmicroscopy/omero-server
    container_name: omero-server
    restart: always
    env_file: .env
    environment:
      CONFIG_omero_db_host: omero-db
      CONFIG_omero_db_user: ${OMERO_DB_USER}
      CONFIG_omero_db_pass: ${OMERO_DB_PASS}
      CONFIG_omero_db_name: ${OMERO_DB_NAME}
      ROOTPASS: ${OMERO_ROOT_PASS}
    volumes:
      - /omero/data:/OMERO
    depends_on:
      db:
        condition: service_healthy
    networks:
      - omero-net
  web:
    image: openmicroscopy/omero-web-standalone
    container_name: omero-web
    restart: always
    env_file: .env
    environment:
      OMEROHOST: omero-server
    ports:
      - "${OMERO_WEB_PORT}"
    depends_on:
      - server
    networks:
      - omero-net
networks:
  omero-net:
volumes:
  omero-db:
```

### Permisos de almacenamiento
Antes de levantar los servicios hay que asignar los permisos a docker para acceder a omero/Data en omeroStorage.
```bash
chown -R 1000:1000 /omero/data
chmod -R 775 /omero/data
```

### Levantar servicios de Omero
Una vez levantados satisfactoriamente, se iniciaran incluso en caso de resetear la máquina.
```bash
docker compose up -d
```

### Verificación del levantamiento de los servicios.
```bash
docker compose ps
```

### Conectarse desde el mismo dispositivo.
Abre cualquier navegador y accede a la siguiente URL:
```bash
localhost:4080
```

## Identificar IP para conectarse desde otro dispositivo
### Asegurate de tener instalado iproute2 gawk
Para instalarlo ejecuta:
```bash
sudo apt update
sudo apt install iproute2 gawk
```

### Para identificar la IP del dispositivo ejecuta:
```bash
ip route show default
```

o para obtener la IP específica:
```bash
ip route show default | awk '{print $9}'
```

Ejemplo de coneccion al servidor mediante IP en navegador (usa la IP de tu dispositivo)
```bash
http://<IP>:4080
http://192.168.0.6:4080
```

## Extiende el espacio de almacenamiento
### Agregando un nuevo disco
Conecta un nuevo disco y verificar que se reconozca
```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```
o
```bash
lsblk -o NAME #para ver únicamente los nombres
```

## Asegurate de estar en el directorio ~/omero
```bash
cd ~/omero
```

## Crea el script “extiende_omero.sh”
Puedes descargar el archivo de: https://github.com/RPintoC/omero-lvm-docker-guide/blob/main/extiende_omero.sh

O puedes crearlo tu mismo:
```bash
nano extiende_omero.sh
```

Contenido del archivo extiende_omero.sh:
```bash
#!/bin/bash
# extiende_omero.sh
# Uso: ./extiende_omero.sh sdc
set -e
if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta este script como root"
    exit 1
fi
if [ -z "$1" ]; then
    echo "Uso: $0 <nombre_del_disco> (ej. sdc)"
    exit 1
fi
DISCO="/dev/$1"
VG="omeroStorage"
LV="omeroData"
MOUNT_POINT="/omero/data"
# Verifica que el disco exista
if [ ! -b "$DISCO" ]; then
    echo "Error: $DISCO no existe"
    exit 1
fi
echo "Creando PV en $DISCO..."
pvcreate "$DISCO"
echo "Agregando $DISCO al VG $VG..."
vgextend "$VG" "$DISCO"
echo "Extendiendo LV $LV al máximo disponible..."
lvextend -l +100%FREE "/dev/$VG/$LV"
echo "Redimensionando filesystem (ext4) en $MOUNT_POINT..."
resize2fs "/dev/$VG/$LV"
echo "¡Listo! Nuevo disco $DISCO agregado a $VG/$LV y filesystem redimensionado."
df -h "$MOUNT_POINT"
redimensionado." df -h "$MOUNT_POINT"
```

## Dale permisos de ejecución
```bash
chmod +x extiende_omero.sh
```

## Ejecuta el script
```bash
./extiende_omero.sh sdc
```

---
# Instrucciones para la creación de grupos y usuarios en OMERO

Estas instrucciones describen cómo crear grupos de trabajo y usuarios en el servidor OMERO.

## Acceso al servidor

- Abre un navegador web y accede a OMERO usando la IP del servidor o localhost si estás trabajando desde la máquina host.

- Inicia sesión con las credenciales de administrador (root).

## Creación de grupos de trabajo

- Una vez dentro de OMERO, en la barra superior, selecciona la opción “Admin”. Esto te llevará a la sección de gestión de usuarios por defecto.

- Para crear un grupo (necesario si aún no existe ninguno):

- Selecciona la pestaña “Groups”.

- Aquí se listan todos los grupos existentes. Para crear uno nuevo, haz clic en “Add new Group”.

- Rellena la información requerida para el grupo (nombre, descripción, etc.).

- Guarda los cambios.

*Consejo: Organiza los grupos de forma lógica según proyectos, departamentos o equipos para facilitar la gestión de usuarios y permisos.*

## Creación de usuarios

- Vuelve a la pestaña “Users” dentro de la sección Admin.

- Haz clic en “Add new User”.

- Completa los campos obligatorios:

  - Nombre de usuario

  - Contraseña

  - Otros campos marcados en rojo.

- En la sección “Groups”, selecciona el grupo al que pertenecerá el usuario (puede ser el grupo recién creado o uno existente).

- Guarda los cambios.

###Verifica que el usuario se ha creado correctamente revisando la lista en la pestaña Users.