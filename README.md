# Guía para la instalacion y configuracion de Omero-Server y Omero-Web con Dockers y LVM

## Requisitos
- Ubuntu 24.04 recién instalado.
- LVM ya configurado por el instalador.
- Acceso como usuario con privilegios sudo (ejecutar sudo su antes de iniciar).
- Un disco adicional (separado del que contiene el SO) (puede ser una partición generada antes de instalar el SO).
- Discos adicionales si vas a extender el almacenamiento.
- Acceso a la Terminal.
---
## Crear un único espacio LVM para OMERO (omeroStorage)
### Verificar que se reconozca el disco secundario
(usualmente “sdb” en caso contrario reemplazar el nombre en las siguientes instrucciones)
```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```

### Limpiar el disco (opcional)
```bash
sudo wipefs -a /dev/sdb
```

### Crear una particion LVM
```bash
sudo parted /dev/sdb --script mklabel gpt
sudo parted /dev/sdb --script mkpart primary 0% 100%
sudo parted /dev/sdb --script set 1 lvm on
```

### Crear el PV (Physical Volume)
```bash
sudo pvcreate /dev/sdb1
```
### Crear el VG (Volume Group) “omeroStorage”
```bash
sudo vgcreate omeroStorage /dev/sdb1
```


### Crear un LV dentro de omeroStorage
```bash
sudo lvcreate -l 100%FREE -n omeroData omeroStorage
```

### Formatear el volumen lógico
```bash
sudo mkfs.ext4 /dev/omeroStorage/omeroData
```
### Crear el punto de montaje
```bash
sudo mkdir -p /omero/data
```

### Ubica el UUID
```bash
blkid /dev/omeroStorage/omeroData
```
### Abre el archivo fstab
```bash
sudo nano /etc/fstab
```
### Agrega la siguiente línea y guarda los cambios
```bash
UUID=<EL_UUID_AQUÍ>  /omero/data  ext4  defaults  0  2
```
### Montar el disco
```bash
sudo mount -a
```
---
## Instalar Docker
### Agregar llaves GPG oficiales de Docker
```bash
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

### Agregar fuentes de repositorio apt
```bash
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF Types: deb URIs: https://download.docker.com/linux/ubuntu Suites: $(. /etc os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") Components: stable Signed-By: /etc/apt/keyrings/docker.asc EOF

sudo apt update
```

### Instalar paquetes docker
```bash
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Verificar la instalación de docker
```bash
sudo systemctl status docker
```
---
## Descargar las imágenes de OMERO
### Descargar omero-server y omero-web
```bash
docker pull openmicroscopy/omero-server
docker pull openmicroscopy/omero-web-standalone
```

### Crear archivo `.env` para variables sensibles
Abrir nano copiar y pegar el siguiente texto, y modificar los valores de la variables a conveniencia:
```bash
# --- Base de datos —
OMERO_DB_USER = db_user
OMERO_DB_PASS = db_password
OMERO_DB_NAME = omero_database
# --- Servidor OMERO —
OMERO_ROOT_PASS = omero_root_pass
OMERO_DATA_DIR = /OMERO
# --- Web —
OMERO_WEB_PORT=80
```

### Crear archivo `docker-compose.yml`
```bash
Abrir nano copiar y pegar el siguiente texto:
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
    ports:
      - "4063:4063"
      - "4064:4064"
    volumes:
      - /omero/data:/OMERO
    depends_on:
      - db
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
      - "${OMERO_WEB_PORT}:4080"
    depends_on:
      - server
    networks:
      - omero-net

networks:
  omero-net:

volumes:
  omero-db:
```
---
## Levantar los servicios
### Antes de levantar los servicios hay que asignar los permisos a docker para acceder a omero/Data en omeroStorage
```bash
sudo chown -R 1000:1000 /omero/data
sudo chmod -R 775 /omero/data
```

### Crear volumen para la base de datos
```bash
docker volume create --name omero-db
```

### Levantar servicios de omero (una vez levantados satisfactoriamente, se iniciaran incluso en caso de resetear la máquina)
```bash
docker compose up -d
```

### Detener servicios de omero (en caso de querer hacer algún cambio)
```bash
docker compose down
```
---
## Identificar IP para conectarse desde otro dispositivo
Asegurate de tener instalado net-tools, para instalarlo ejecuta:
```bash
sudo apt install net-tools
```

### Si la pc esta conectada al WIFI ()
```bash
ifconfig wlo1 | grep 'inet ' | awk '{print $2}'
```

### Si la pc esta conectada por Ethernet
```bash
ifconfig enp4s0 | grep 'inet ' | awk '{print $2}'
```

### `wlo1` y `wlo1` pueden no existir en todos los sistemas
En este caso ejecutar:
```bash
ifconfig
```
y buscar `wlan0`, `eth0`, `enp3s0` o similares.

### Ejemplo de coneccion al servidor mediante IP en navegador
```bash
<IP>:80
```
```bash
10.90.6.31:80
```
---
## Agregar nuevos discos a omeroStorage (extender LVM)
### Verificar que se reconozca el nuevo disco secundario
Usualmente “sdc” en caso contrario reemplazar el nombre en las siguientes instrucciones
```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```

### Crea el script “extiende_omero.sh”
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
```

### Dale permisos de ejecución
```bash
chmod +x extiende_omero.sh
```

### Ejecuta el script
```bash
sudo ./extiende_omero.sh sdc
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