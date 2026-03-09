#!/usr/bin/env bash
# Monitoreo SMTP por ventana móvil – versión CRON optimizada
# Producción estable – Zimbra 8.8.15
# Autor: Luis Zambrano (Optimizado)

AUTOR="Luis Zambrano"
DB="/opt/script/DBZIMBRA.DB"
LOG="/var/log/zimbra.log"
BITACORA="/var/log/monitoreo_smtp.log"

LIMITE_ENVIO=100
VENTANA_MIN=10
ADMINS="marlon.macias@13d06.mspz4.gob.ec,luis.zambrano@13d06.mspz4.gob.ec"
SIMULACION=false

# Asegurar permisos y existencia de base de datos
touch "$BITACORA"
chmod 640 "$BITACORA"
chown root:zimbra "$BITACORA"

if [ ! -f "$DB" ]; then
    sqlite3 "$DB" "CREATE TABLE notificacion (id INTEGER PRIMARY KEY, fecha TEXT, evento INTEGER, usuario TEXT);"
fi

exec >> "$BITACORA" 2>&1
set -o pipefail

echo "=================================================="
echo "$(date '+%Y-%m-%d %H:%M:%S') - Inicio análisis SMTP"
echo "Ventana: $VENTANA_MIN minutos"
echo "Límite: $LIMITE_ENVIO"
echo "=================================================="

# -------------------------
# Obtener minutos válidos
# -------------------------
FECHAS_VALIDAS=$(for i in $(seq 0 $((VENTANA_MIN-1))); do date -d "-$i minutes" '+%b %e %H:%M'; done | tr '\n' '|' | sed 's/|$//')

declare -A ENVIOS

# -------------------------
# Procesar logs (Corrección de subshell con redirección de procesos)
# -------------------------
while read -r LINEA; do

    # Intenta obtener usuario de sasl_username, si falla, busca en from=<
    USUARIO=$(echo "$LINEA" | grep -oP 'sasl_username=\K[^ ]+')
    [ -z "$USUARIO" ] && USUARIO=$(echo "$LINEA" | grep -oP 'from=<\K[^>]+')
    
    [ -z "$USUARIO" ] && continue

    # Obtener destinatarios (nrcpt)
    NRCPT=$(echo "$LINEA" | grep -oP 'nrcpt=\K[0-9]+')
    [ -z "$NRCPT" ] && NRCPT=1

    ENVIOS["$USUARIO"]=$(( ${ENVIOS["$USUARIO"]:-0} + NRCPT ))

done < <(grep -E "$FECHAS_VALIDAS" "$LOG" | grep -E "sasl_username=|from=<")

echo "Resumen detectado:"

for U in "${!ENVIOS[@]}"; do

    echo "${ENVIOS[$U]} envíos - $U"

    if [ "${ENVIOS[$U]}" -ge "$LIMITE_ENVIO" ]; then

        EXISTE=$(sqlite3 "$DB" "SELECT COUNT(*) FROM notificacion WHERE usuario='$U' AND evento=2 AND fecha > datetime('now','-$VENTANA_MIN minutes');")

        if [ "$EXISTE" -eq 0 ]; then

            if [ "$SIMULACION" = false ]; then
                # Ejecución directa como usuario zimbra para evitar overhead de su -
                /opt/zimbra/bin/zmprov ma "$U" zimbraAccountStatus locked
                echo "ALERTA: Cuenta $U bloqueada."
            else
                echo "Simulación activa: bloqueo omitido para $U."
            fi

            sqlite3 "$DB" "INSERT INTO notificacion (fecha,evento,usuario) VALUES('$(date '+%Y-%m-%d %H:%M:%S')',2,'$U');"

            {
            echo "From: Soporte TICs <soporte@13d06.mspz4.gob.ec>"
            echo "To: $ADMINS"
            echo "Subject: [ALERTA CRÍTICA] Bloqueo automático por spam"
            echo ""
            echo "Alerta de Seguridad Zimbra"
            echo "--------------------------"
            echo "Usuario: $U"
            echo "Correos enviados: ${ENVIOS[$U]}"
            echo "Ventana: $VENTANA_MIN minutos"
            echo "Estado: Bloqueado automáticamente"
            echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "--------------------------"
            echo "Este es un mensaje automático generado por el sistema de monitoreo."
            } | /opt/zimbra/common/sbin/sendmail -t
        fi
    fi
done

echo "Fin ejecución"
echo ""
