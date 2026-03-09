#!/bin/bash
# Monitoreo SMTP Entrante - Producción optimizado con IPSET
# Luis Zambrano - 2026 - Versión IPSET V2.4 (Fix Variable Scope)

LOG="/var/log/monitoreo_smtp_entrante.log"
ZIMBRA_LOG="/var/log/zimbra.log"
BLACKLIST="/opt/script/listanegra.conf"
WHITELIST_DOMINIOS="/opt/whitelist_dominios_entrantes.conf"
ADMINS="soporte@13d06.mspz4.gob.ec,luis.zambrano@13d06.mspz4.gob.ec"

UMBRAL_CONEXIONES=40
SIMULACION=false
OFFSET_FILE="/opt/script/last_offset_entrantes.txt"

declare -A CONEXIONES_IP

# Inicializar archivos
touch "$BLACKLIST" "$WHITELIST_DOMINIOS" "$OFFSET_FILE"

# --- CONFIGURACIÓN DE IPSET Y IPTABLES ---
ipset create LISTA_NEGRA hash:ip 2>/dev/null
iptables -C INPUT -m set --match-set LISTA_NEGRA src -j DROP 2>/dev/null || \
iptables -I INPUT -m set --match-set LISTA_NEGRA src -j DROP

# --- GESTIÓN DE OFFSET ---
LAST_OFFSET=0
[ -f "$OFFSET_FILE" ] && LAST_OFFSET=$(cat "$OFFSET_FILE")
TOTAL_LINES=$(wc -l < "$ZIMBRA_LOG")
if [ "$TOTAL_LINES" -lt "$LAST_OFFSET" ]; then LAST_OFFSET=0; fi

# --- PROCESAMIENTO DE LOGS (CORREGIDO PARA EVITAR SUBSHELL) ---
# Guardamos las líneas en una variable temporal o archivo para que el array persista
LOG_SEGMENT=$(sed -n "$((LAST_OFFSET+1)),$TOTAL_LINES p" "$ZIMBRA_LOG")

while read -r LINEA; do
    IP=$(echo "$LINEA" | grep -oP 'connect from .*?\[\K[0-9.]+')
    [ -z "$IP" ] && continue
    [[ "$IP" =~ ^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]] && continue

    DOMINIO=$(echo "$LINEA" | grep -oP 'from=<.*@\K[^>]+')
    if [ -n "$DOMINIO" ] && grep -qx "$DOMINIO" "$WHITELIST_DOMINIOS"; then
        continue
    fi
    CONEXIONES_IP["$IP"]=$(( ${CONEXIONES_IP["$IP"]:-0} + 1 ))
done <<< "$LOG_SEGMENT"

# --- AHORA SÍ: EL CONTEO TENDRÁ VALOR AQUÍ ---
IPS_ENCONTRADAS=${#CONEXIONES_IP[@]}

# --- PROCESAMIENTO DE RESULTADOS Y ALERTAS ---
for IP in "${!CONEXIONES_IP[@]}"; do
    TOTAL=${CONEXIONES_IP[$IP]}

    if [ "$TOTAL" -ge "$UMBRAL_CONEXIONES" ]; then
        if grep -qx "$IP" "$BLACKLIST"; then
            continue
        fi

        if [ "$SIMULACION" = false ]; then
            echo "$IP" >> "$BLACKLIST"
            ipset add LISTA_NEGRA "$IP" 2>/dev/null
            ACCION="BLOQUEADA (IPSET)"
        else
            ACCION="SIMULADA"
        fi

        # Alerta Email
        {
            echo "From: Soporte TICs <soporte@13d06.mspz4.gob.ec>"
            echo "To: $ADMINS"
            echo "Subject: [ALERTA] $ACCION IP SMTP: $IP"
            echo ""
            echo "IP: $IP"
            echo "Conexiones: $TOTAL"
            echo "Acción: $ACCION"
            echo "Fecha: $(date)"
            echo "--------------------------------------------------"
        } | /opt/zimbra/common/sbin/sendmail -t

        echo "$(date '+%Y-%m-%d %H:%M:%S') - CRÍTICO: IP $IP bloqueada con $TOTAL conexiones" >> "$LOG"
    fi
done
 # 1. ACCIÓN DE SEGURIDAD (Sincronización del Firewall)
if [ "$SIMULACION" = false ]; then
    cat "$BLACKLIST" | xargs -I {} ipset add LISTA_NEGRA {} -exist 2>/dev/null
    echo "Sincronización completa de la lista negra realizada."
fi
# --- REPORTE DE EJECUCIÓN (LATIDO) ---
{
    echo "--------------------------------------------------"
    echo "Ejecución: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Líneas nuevas leídas: $((TOTAL_LINES - LAST_OFFSET))"
    echo "IPs externas analizadas: $IPS_ENCONTRADAS"
    echo "Estado Simulación: $SIMULACION"
    echo "--------------------------------------------------"
} >> "$LOG"

echo "$TOTAL_LINES" > "$OFFSET_FILE"
