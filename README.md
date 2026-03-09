# Zimbra Security Scripts

Colección de scripts para protección de servidores Zimbra contra:

- Spam saliente por cuentas comprometidas
- Ataques SMTP entrantes
- Bloqueo automático mediante iptables
- Monitoreo de actividad sospechosa

Este repositorio contiene herramientas experimentales y scripts en desarrollo.

## Scripts actuales

### block_spam_accounts_permanent.sh
Monitorea el SMTP saliente para detectar cuentas comprometidas que envían spam masivo.

Acciones:
- Detecta envíos masivos
- Identifica usuario responsable
- Bloquea la cuenta comprometida

### monitoreo_smtp_entrante.sh
Monitorea conexiones SMTP entrantes y bloquea IP sospechosas mediante iptables.

Acciones:
- Detecta múltiples conexiones SMTP
- Identifica posibles ataques de spam
- Aplica bloqueo automático por firewall

## Rama laboratorio

La rama **laboratorio** contiene:

- scripts en pruebas
- mejoras experimentales
- cambios que aún no están en producción

Los scripts probados pasan luego a la rama **main**.

## Requisitos

Servidor Linux con:

- bash
- iptables
- acceso a logs de Zimbra

## Uso

Ejecutar los scripts como usuario con permisos administrativos.
