# OMERO Server y OMERO Web con Docker y LVM

Guía práctica para instalar y configurar **OMERO Server** y **OMERO Web** usando **Docker** sobre **Ubuntu 24.04**, con almacenamiento gestionado mediante **LVM**. Pensado para entornos de laboratorio y servidores on‑premise.

---

## Requisitos

- Ubuntu 24.04 recién instalado
- LVM configurado durante la instalación del SO
- Usuario con privilegios `sudo`
- Un disco adicional exclusivo para datos de OMERO
- Acceso a terminal

---

## 1. Configuración de almacenamiento con LVM

### Verificar discos disponibles

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```

> En esta guía se asume `/dev/sdb` como disco de datos.

### (Opcional) Limpiar disco

```bash
sudo wipefs -a /dev/sdb
```

### Crear partición LVM

```bash
sudo parted /dev/sdb --script mklabel gpt
sudo parted /dev/sdb --script mkpart primary 0% 100%
sudo parted /dev/sdb --script set 1 lvm on
```

### Crear volumen físico (PV)

```bash
sudo pvcreate /dev/sdb1
```

### Crear grupo de volúmenes (VG)

```bash
sudo vgcreate omeroStorage /dev/sdb1
```

### Crear volumen lógico (LV)

```bash
sudo lvcreate -l 100%FREE -n omeroData omeroStorage
```

### Formatear y montar

```bash
sudo mkfs.ext4 /dev/omeroStorage/omeroData
sudo mkdir -p /omero/data
sudo blkid /dev/omeroStorage/omeroData
sudo nano /etc/fstab
```

Agregar:

```text
UUID=<UUID> /omero/data ext4 defaults 0 2
```

```bash
sudo mount -a
```

---

## 2. Instalación de Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

```bash
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl status docker
```

---

## 3. Descarga de imágenes OMERO

```bash
docker pull openmicroscopy/omero-server
docker pull openmicroscopy/omero-web-standalone
```

---

## 4. Variables de entorno (.env)

Crear archivo `.env`:

```env
# Base de datos
OMERO_DB_USER=db_user
OMERO_DB_PASS=db_password
OMERO_DB_NAME=omero_database

# Servidor OMERO
OMERO_ROOT_PASS=omero_root_pass
OMERO_DATA_DIR=/OMERO

# Web
OMERO_WEB_PORT=80
```

---

## 5. Docker Compose

Crear `docker-compose.yml`:

```yaml
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

## 6. Levantar servicios

```bash
sudo chown -R 1000:1000 /omero/data
sudo chmod -R 775 /omero/data

docker volume create omero-db
docker compose up -d
```

Detener servicios:

```bash
docker compose down
```

---

## 7. Acceso a OMERO Web

Instalar herramientas de red:

```bash
sudo apt install net-tools
```

Obtener IP:

```bash
ifconfig | grep inet
```

Acceder desde navegador:

```text
http://<IP>:80
```

---

## 8. Extender almacenamiento LVM

Script `extiende_omero.sh`:

```bash
#!/bin/bash
set -e
DISCO="/dev/$1"
VG="omeroStorage"
LV="omeroData"
MOUNT_POINT="/omero/data"

pvcreate "$DISCO"
vgextend "$VG" "$DISCO"
lvextend -l +100%FREE "/dev/$VG/$LV"
resize2fs "/dev/$VG/$LV"
df -h "$MOUNT_POINT"
```

```bash
chmod +x extiende_omero.sh
sudo ./extiende_omero.sh sdc
```

---

## 9. Gestión de usuarios y grupos

1. Acceder a OMERO Web como `root`
2. Ir a **Admin → Groups** y crear grupos de trabajo
3. Ir a **Users → Add new User**
4. Asignar grupo, credenciales y guardar

---

## Notas finales

- El almacenamiento de imágenes vive fuera de los contenedores
- Los servicios sobreviven reinicios del sistema
- Ideal para producción básica o entornos académicos

---

**Autor:** Documentación adaptada para uso en GitHub

