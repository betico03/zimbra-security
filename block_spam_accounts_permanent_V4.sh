 #!/usr/bin/env bash
 # Monitoreo SMTP por ventana móvil – versión CRON optimizada
 # Producción estable – Zimbra 8.8.15
 # Autor: Luis Zambrano (Optimizado)
 
-AUTOR="Luis Zambrano"
-DB="/opt/script/DBZIMBRA.DB"
-LOG="/var/log/zimbra.log"
-BITACORA="/var/log/monitoreo_smtp.log"
+set -euo pipefail
 
-LIMITE_ENVIO=100
-VENTANA_MIN=10
-ADMINS="xxx.xxxx@midominio.com,xxx.xxxx@midominio.com"
-SIMULACION=false
+AUTOR="Luis Zambrano"
+DB="${DB:-/opt/script/DBZIMBRA.DB}"
+LOG="${LOG:-/var/log/zimbra.log}"
+BITACORA="${BITACORA:-/var/log/monitoreo_smtp.log}"
+
+LIMITE_ENVIO="${LIMITE_ENVIO:-100}"
+VENTANA_MIN="${VENTANA_MIN:-10}"
+ADMINS="${ADMINS:-marlon.macias@13d06.mspz4.gob.ec,luis.zambrano@13d06.mspz4.gob.ec}"
+SIMULACION="${SIMULACION:-false}"
+ZMPROV_BIN="${ZMPROV_BIN:-/opt/zimbra/bin/zmprov}"
+SENDMAIL_BIN="${SENDMAIL_BIN:-/opt/zimbra/common/sbin/sendmail}"
+
+sql_escape() {
+    printf "%s" "$1" | sed "s/'/''/g"
+}
+
+run_sql() {
+    local query="$1"
+    sqlite3 "$DB" "$query"
+}
 
 # Asegurar permisos y existencia de base de datos
+mkdir -p "$(dirname "$BITACORA")" "$(dirname "$DB")"
 touch "$BITACORA"
 chmod 640 "$BITACORA"
-chown root:zimbra "$BITACORA"
+chown root:zimbra "$BITACORA" 2>/dev/null || true
 
 if [ ! -f "$DB" ]; then
-    sqlite3 "$DB" "CREATE TABLE notificacion (id INTEGER PRIMARY KEY, fecha TEXT, evento INTEGER, usuario TEXT);"
+    run_sql "CREATE TABLE notificacion (id INTEGER PRIMARY KEY, fecha TEXT, evento INTEGER, usuario TEXT);"
 fi
 
 exec >> "$BITACORA" 2>&1
-set -o pipefail
 
 echo "=================================================="
 echo "$(date '+%Y-%m-%d %H:%M:%S') - Inicio análisis SMTP"
 echo "Ventana: $VENTANA_MIN minutos"
 echo "Límite: $LIMITE_ENVIO"
+echo "Simulación: $SIMULACION"
 echo "=================================================="
 
+if [ ! -f "$LOG" ]; then
+    echo "ERROR: No existe el log: $LOG"
+    exit 1
+fi
+
 # -------------------------
 # Obtener minutos válidos
 # -------------------------
-FECHAS_VALIDAS=$(for i in $(seq 0 $((VENTANA_MIN-1))); do date -d "-$i minutes" '+%b %e %H:%M'; done | tr '\n' '|' | sed 's/|$//')
+FECHAS_VALIDAS=$(for i in $(seq 0 $((VENTANA_MIN - 1))); do LC_ALL=C date -d "-$i minutes" '+%b %e %H:%M'; done | tr '\n' '|' | sed 's/|$//')
 
 declare -A ENVIOS
 
 # -------------------------
-# Procesar logs (Corrección de subshell con redirección de procesos)
+# Procesar logs en una sola pasada
 # -------------------------
-while read -r LINEA; do
-
-    # Intenta obtener usuario de sasl_username, si falla, busca en from=<
-    USUARIO=$(echo "$LINEA" | grep -oP 'sasl_username=\K[^ ]+')
-    [ -z "$USUARIO" ] && USUARIO=$(echo "$LINEA" | grep -oP 'from=<\K[^>]+')
-    
+while read -r USUARIO NRCPT; do
     [ -z "$USUARIO" ] && continue
-
-    # Obtener destinatarios (nrcpt)
-    NRCPT=$(echo "$LINEA" | grep -oP 'nrcpt=\K[0-9]+')
     [ -z "$NRCPT" ] && NRCPT=1
-
     ENVIOS["$USUARIO"]=$(( ${ENVIOS["$USUARIO"]:-0} + NRCPT ))
-
-done < <(grep -E "$FECHAS_VALIDAS" "$LOG" | grep -E "sasl_username=|from=<")
+done < <(
+    awk -v fechas="$FECHAS_VALIDAS" '
+    $0 ~ fechas && ($0 ~ /sasl_username=|from=</) {
+        usuario=""
+        nrcpt=1
+
+        if (match($0, /sasl_username=[^ ,]+/)) {
+            usuario=substr($0, RSTART, RLENGTH)
+            sub(/^sasl_username=/, "", usuario)
+        } else if (match($0, /from=<[^>]+>/)) {
+            usuario=substr($0, RSTART, RLENGTH)
+            sub(/^from=</, "", usuario)
+            sub(/>$/, "", usuario)
+        }
+
+        if (match($0, /nrcpt=[0-9]+/)) {
+            valor=substr($0, RSTART, RLENGTH)
+            sub(/^nrcpt=/, "", valor)
+            nrcpt=valor + 0
+        }
+
+        if (usuario != "") {
+            print usuario, nrcpt
+        }
+    }' "$LOG"
+)
 
 echo "Resumen detectado:"
 
 for U in "${!ENVIOS[@]}"; do
-
     echo "${ENVIOS[$U]} envíos - $U"
 
     if [ "${ENVIOS[$U]}" -ge "$LIMITE_ENVIO" ]; then
-
-        EXISTE=$(sqlite3 "$DB" "SELECT COUNT(*) FROM notificacion WHERE usuario='$U' AND evento=2 AND fecha > datetime('now','-$VENTANA_MIN minutes');")
+        U_SQL=$(sql_escape "$U")
+        EXISTE=$(run_sql "SELECT COUNT(*) FROM notificacion WHERE usuario='$U_SQL' AND evento=2 AND fecha > datetime('now','-$VENTANA_MIN minutes');")
 
         if [ "$EXISTE" -eq 0 ]; then
-
-            if [ "$SIMULACION" = false ]; then
-                # Ejecución directa como usuario zimbra para evitar overhead de su -
-                /opt/zimbra/bin/zmprov ma "$U" zimbraAccountStatus locked
-                echo "ALERTA: Cuenta $U bloqueada."
+            BLOQUEADO="no"
+
+            if [ "$SIMULACION" = "false" ]; then
+                if "$ZMPROV_BIN" ma "$U" zimbraAccountStatus locked; then
+                    BLOQUEADO="si"
+                    echo "ALERTA: Cuenta $U bloqueada."
+                else
+                    echo "ERROR: no se pudo bloquear la cuenta $U"
+                    continue
+                fi
             else
+                BLOQUEADO="simulacion"
                 echo "Simulación activa: bloqueo omitido para $U."
             fi
 
-            sqlite3 "$DB" "INSERT INTO notificacion (fecha,evento,usuario) VALUES('$(date '+%Y-%m-%d %H:%M:%S')',2,'$U');"
-
-            {
-            echo "From: Soporte TICs <xxx.xxxx@midominio.com>"
-            echo "To: $ADMINS"
-            echo "Subject: [ALERTA CRÍTICA] Bloqueo automático por spam"
-            echo ""
-            echo "Alerta de Seguridad Zimbra"
-            echo "--------------------------"
-            echo "Usuario: $U"
-            echo "Correos enviados: ${ENVIOS[$U]}"
-            echo "Ventana: $VENTANA_MIN minutos"
-            echo "Estado: Bloqueado automáticamente"
-            echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
-            echo "--------------------------"
-            echo "Este es un mensaje automático generado por el sistema de monitoreo."
-            } | /opt/zimbra/common/sbin/sendmail -t
+            if ! run_sql "INSERT INTO notificacion (fecha,evento,usuario) VALUES('$(date '+%Y-%m-%d %H:%M:%S')',2,'$U_SQL');"; then
+                echo "ERROR: no se pudo registrar evento para $U"
+                continue
+            fi
+
+            if ! {
+                echo "From: Soporte TICs <xxx.xxxx@midominio.com>"
+                echo "To: $ADMINS"
+                echo "Subject: [ALERTA CRÍTICA] Bloqueo automático por spam"
+                echo ""
+                echo "Alerta de Seguridad Zimbra"
+                echo "--------------------------"
+                echo "Usuario: $U"
+                echo "Correos enviados: ${ENVIOS[$U]}"
+                echo "Ventana: $VENTANA_MIN minutos"
+                if [ "$BLOQUEADO" = "si" ]; then
+                    echo "Estado: Bloqueado automáticamente"
+                elif [ "$BLOQUEADO" = "simulacion" ]; then
+                    echo "Estado: Simulación activa (sin bloqueo)"
+                else
+                    echo "Estado: Error en bloqueo"
+                fi
+                echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
+                echo "--------------------------"
+                echo "Este es un mensaje automático generado por el sistema de monitoreo."
+            } | "$SENDMAIL_BIN" -t; then
+                echo "ERROR: fallo al enviar notificación para $U"
+            fi
         fi
     fi
 done
 
 echo "Fin ejecución"
 echo ""
