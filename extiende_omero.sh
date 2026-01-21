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
