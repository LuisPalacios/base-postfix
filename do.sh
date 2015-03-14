#!/bin/bash
#
# Punto de entrada para el servicio Postfix
#
# Activar el debug de este script:
# set -eux
#

##################################################################
#
# main
#
##################################################################

# Averiguar si necesito configurar Postfix por primera vez
#
CONFIG_DONE="/.config_postfix_done"
NECESITA_PRIMER_CONFIG="si"
if [ -f ${CONFIG_DONE} ] ; then
    NECESITA_PRIMER_CONFIG="no"
fi

##################################################################
#
# VARIABLES OBLIGATORIAS
#
##################################################################


## Servidor:Puerto por el que conectar con el servidor MYSQL
#
if [ -z "${MYSQL_LINK}" ]; then
	echo >&2 "error: falta el Servidor:Puerto del servidor MYSQL: MYSQL_LINK"
	exit 1
fi
mysqlHost=${MYSQL_LINK%%:*}
mysqlPort=${MYSQL_LINK##*:}

## Servidor:Puerto por el que escucha el chatarrero (amavisd-new/clamav/spamassassin)
#
if [ -z "${CHATARRERO_LINK}" ]; then
	echo >&2 "error: falta el Servidor:Puerto por el que escucha fluentd, variable: CHATARRERO_LINK"
	exit 1
fi
chatarreroHost=${CHATARRERO_LINK%%:*}
chatarreroPort=${CHATARRERO_LINK##*:}

## Servidor:Puerto por el que escucha el agregador de Logs (fluentd)
#
if [ -z "${FLUENTD_LINK}" ]; then
	echo >&2 "error: falta el Servidor:Puerto por el que escucha fluentd, variable: FLUENTD_LINK"
	exit 1
fi
fluentdHost=${FLUENTD_LINK%%:*}
fluentdPort=${FLUENTD_LINK##*:}

## Variables para crear la BD del servicio
#
if [ -z "${SERVICE_POSTMASTER}" ]; then
	echo >&2 "error: falta la variable SERVICE_POSTMASTER"
	exit 1
fi
if [ -z "${SERVICE_MYHOSTNAME}" ]; then
	echo >&2 "error: falta la variable SERVICE_MYHOSTNAME"
	exit 1
fi
if [ -z "${SERVICE_MYDOMAIN}" ]; then
	echo >&2 "error: falta la variable SERVICE_MYDOMAIN"
	exit 1
fi

## Variables para acceder a la BD de PostfixAdmin donde están
#  todos los usuarios, contraseñas, dominios, etc...
#
if [ -z "${MAIL_DB_USER}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_USER"
	exit 1
fi
if [ -z "${MAIL_DB_PASS}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_PASS"
	exit 1
fi
if [ -z "${MAIL_DB_NAME}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_NAME"
	exit 1
fi


##################################################################
#
# Usuario/Grupo "vmail" - owner directorio donde residen los mails 
# recibidos vía el contendor postfix o leídos desde el contenedor
# courier-imap. 
#
# En ambos contenedores (postfix y courier-imap) debo montar el 
# directorio externo persistente elegido para dejar los mails. 
#
# run: -v /Apps/data/vmail:/data/vmail
#
# Además debo tener el mismo usuario como propietario de dicha 
# estructura de directorios, así que en ambos contenedores de 
# postfix y courier-imap creo el usuario vmail con mismo UID/GID
#
##################################################################
ret=false
getent passwd $1 >/dev/null 2>&1 && ret=true
if $ret; then
    echo ""
else
	groupadd -g 3008 vmail
	useradd -u 3001 -g vmail -M -d /data/vmail -s /bin/false vmail
fi

##################################################################
#
# PREPARAR EL CONTAINER POR PRIMERA VEZ
#
##################################################################

# Necesito configurar por primera vez?
#
if [ ${NECESITA_PRIMER_CONFIG} = "si" ] ; then

	# Muestro las variables
	#
	echo >&2 "Realizo la instalación por primera vez !!!!"
	echo >&2 "-------------------------------------------"
	echo >&2 "SERVICE_POSTMASTER: ${SERVICE_POSTMASTER}"
	echo >&2 "SERVICE_MYHOSTNAME: ${SERVICE_MYHOSTNAME}"
	echo >&2 "SERVICE_MYDOMAIN: ${SERVICE_MYDOMAIN}"
	echo >&2 "-------------------------------------------"


	############
	#
	# Supervisor
	# 
	############
	
	### 
	### INICIO FICHERO  /etc/supervisor/conf.d/supervisord.conf
	### ------------------------------------------------------------------------------------------------
	cat > /etc/supervisor/conf.d/supervisord.conf <<-EOF_SUPERVISOR
	
	[unix_http_server]
	file=/var/run/supervisor.sock 					; path to your socket file
	
	[inet_http_server]
	port = 0.0.0.0:9001								; allow to connect from web browser
	
	[supervisord]
	logfile=/var/log/supervisor/supervisord.log 	; supervisord log file
	logfile_maxbytes=50MB 							; maximum size of logfile before rotation
	logfile_backups=10 								; number of backed up logfiles
	loglevel=error 									; info, debug, warn, trace
	pidfile=/var/run/supervisord.pid 				; pidfile location
	minfds=1024 									; number of startup file descriptors
	minprocs=200 									; number of process descriptors
	user=root 										; default user
	childlogdir=/var/log/supervisor/ 				; where child log files will live
	
	nodaemon=false 									; run supervisord as a daemon when debugging
	;nodaemon=true 									; run supervisord interactively
	 
	[rpcinterface:supervisor]
	supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
	 
	[supervisorctl]
	serverurl=unix:///var/run/supervisor.sock		; use a unix:// URL for a unix socket 
	
	[program:postfix]
	process_name = master
	directory = /etc/postfix
	command = /usr/sbin/postfix -c /etc/postfix start
	startsecs = 0
	autorestart = false
	
	[program:rsyslog]
	process_name = rsyslogd
	command=/usr/sbin/rsyslogd -n
	startsecs = 0
	autorestart = true
	
	#
	# DESCOMENTAR PARA DEBUG o SI QUIERES SSHD
	#
	#[program:sshd]
	#process_name = sshd
	#command=/usr/sbin/sshd -D
	#startsecs = 0
	#autorestart = true
	
	EOF_SUPERVISOR
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/supervisor/conf.d/supervisord.conf  
	### 



	#####################
    #
    # postfix / master.cf ((-vvv al final para activar debug, quitar en la versión final))
    #
	#####################
	#
    # Servidor SMTP en 25,2525. 
    # Nota: Los clientes podrán autenticar por el puerto 25 y 2525, usando STARTTLS (ver main.cf)
    # Por el 25 podrán recibirse correos (desde otros servidores) sin autenticar, pero por el 
    # puerto 2525 solo se aceptarán correos si hay autenticación.
    # ==============
    postconf -M smtp/inet="smtp       inet  n       -       n       -       -       smtpd"
 	
    postconf -M 2525/inet="2525       inet  n       -       n       -       -       smtpd"    
	postconf -P 2525/inet/smtpd_sasl_auth_enable=yes
	postconf -P 2525/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject

    # Servidor SMTPS en puerto 465 desactivado !!!!. De hecho en el año 1998 el IANA 
    # revocó la asignación del puerto 465 a SMTPS, cuando se introdujo STARTTLS. 
    # Conclusión: Desactivo SMTPS para que no se use SSL2/SSL3, simplemente "NO" ejecuto
    # los tres comandos siguientes, que lo activarían.
    #postconf -M smtps/inet="smtps     inet  n       -       n       -       -       smtpd"
	#postconf -P smtps/inet/smtpd_sasl_auth_enable=yes
	#postconf -P smtps/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject
  
    # Amavisd-new -- "Cliente SMTP por 10024 y Servidor SMTP en 10025"    
	# ===========
	## Cliente SMTP dedicado para reenviar mails a amavisd-new:10024
	#
	#echo "amavisfeed      10024/tcp" >> /etc/services
	postconf -M amavisfeed/unix="amavisfeed unix -      -       n       -       2       smtp"
	postconf -P amavisfeed/unix/smtp_data_done_timeout=1200
	postconf -P amavisfeed/unix/smtp_send_xforward_command=yes
	postconf -P amavisfeed/unix/disable_dns_lookups=yes
	postconf -P amavisfeed/unix/max_use=20
	#
	## Servidor SMTP dedicado en 10025 para las respuesta de amavisd-new
	#
	postconf -M 10025/inet="10025     inet  n       -       n       -       -       smtpd"    
	postconf -P 10025/inet/content_filter=
	postconf -P 10025/inet/smtpd_delay_reject=no
	postconf -P 10025/inet/smtpd_restriction_classes=
	postconf -P 10025/inet/smtpd_client_restrictions="permit_mynetworks,reject"
	postconf -P 10025/inet/smtpd_helo_restrictions=
	postconf -P 10025/inet/smtpd_sender_restrictions=
	postconf -P 10025/inet/smtpd_recipient_restrictions="permit_mynetworks,reject"
	postconf -P 10025/inet/smtpd_data_restrictions="reject_unauth_pipelining"
	postconf -P 10025/inet/smtpd_restriction_classes=
	postconf -P 10025/inet/mynetworks="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16"
	postconf -P 10025/inet/smtpd_error_sleep_time=0
	postconf -P 10025/inet/smtpd_soft_error_limit=1001
	postconf -P 10025/inet/smtpd_hard_error_limit=1000
	postconf -P 10025/inet/smtpd_client_connection_count_limit=0
    postconf -P 10025/inet/smtpd_client_connection_rate_limit=0
    postconf -P 10025/inet/receive_override_options="no_header_body_checks,no_unknown_recipient_checks,no_milters"
    postconf -P 10025/inet/local_header_rewrite_clients=     
	postconf -P 10025/inet/strict_rfc821_envelopes=yes
	postconf -P 10025/inet/local_recipient_maps=
	postconf -P 10025/inet/relay_recipient_maps=



	#####################
    #
    # postfix / main.cf 
    #
	#####################
	#
	postconf -e myhostname=${SERVICE_MYHOSTNAME}
	postconf -e mydomain=${SERVICE_MYDOMAIN}
	postconf -e mydestination="\$myhostname, localhost.\$mydomain, localhost"
	postconf -e mynetworks="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8"
	postconf -e home_mailbox="Maildir/"
	postconf -e inet_protocols=ipv4
	
	# RBL
	postconf -e smtpd_client_restrictions="permit_mynetworks, \
                                           permit_sasl_authenticated, \
                                           reject_unauth_destination, \
                                           reject_rbl_client zen.spamhaus.org=127.0.0.10 \
                                           reject_rbl_client zen.spamhaus.org=127.0.0.11, \
                                           reject_rbl_client zen.spamhaus.org, \
                                           reject_rbl_client bl.spamcop.net, \
                                           reject_rbl_client cbl.abuseat.org, \
                                           permit"        
    postconf -e rbl_reply_maps="\${stress?hash:/etc/postfix/rbl_reply_maps}"
    
    cat > /etc/postfix/rbl_reply_maps <<-EOF_REPLY_MAPS
	zen.spamhaus.org=127.0.0.11 521 4.7.1 Service unavailable;
	\$rbl_class [\$rbl_what] blocked using
	\$rbl_domain\${rbl_reason?; \$rbl_reason}
	EOF_REPLY_MAPS
	
	# SASL
	postconf -e smtp_sasl_type=cyrus
	postconf -e smtpd_sasl_auth_enable=yes
	postconf -e smtpd_sasl_security_options=noanonymous
	postconf -e broken_sasl_auth_clients=yes
	postconf -e smtpd_sasl_local_domain=
	postconf -e smtpd_recipient_restrictions="permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination"
    
	# TLS/SSL
	postconf -e smtpd_tls_mandatory_protocols=!SSLv2,!SSLv3
	postconf -e smtp_use_tls=yes
	postconf -e smtp_tls_note_starttls_offer=yes
	postconf -e smtpd_use_tls=yes
	postconf -e smtpd_tls_key_file="/etc/ssl/private/postfix.key"
	postconf -e smtpd_tls_cert_file="/etc/ssl/certs/postfix.pem"
	postconf -e smtpd_tls_received_header=yes
	postconf -e smtpd_tls_security_level=may
	postconf -e smtpd_tls_auth_only=yes
	
	# amavisd-new ( REENVÍA TODO EL MAIL ENTRANTE HACIA EL CHATARRERO !!!!)
	# Estas tres líneas provocan que cada vez que llega un mail se reenvía al contenedor
	# donde está amavisd-new/clamav/spamassassin (lo que llamo el chatarrero)
	postconf -e biff=no
	postconf -e empty_address_recipient=MAILER-DAEMON
	postconf -e queue_minfree=120000000
	# syntax @ http://www.postfix.org/smtp.8.html
	postconf -e content_filter="amavisfeed:${chatarreroHost}:${chatarreroPort}"

	#	
	#postconf -e smtpd_sasl_security_options=noanonymous,noplaintext,nodictionary

	# Que "NO" se utilice chroot en ningún servicio...
	postconf -F '*/*/chroot = n'

	# Usuario vmail:vmail
	postconf -e virtual_minimum_uid=1000
	postconf -e virtual_gid_maps=static:3008
	postconf -e virtual_uid_maps=static:3001

	# A partir de que directorio se crean la estructura Maildir
	postconf -e virtual_mailbox_base="/data/vmail/"
	postconf -e virtual_mailbox_limit=112400000

	# Listado de dominios desde MySQL
	postconf -e virtual_mailbox_domains=proxy:mysql:/etc/postfix/mysql_virtual_domains_maps.cf

	# Listado de alias desde MySQL
	postconf -e virtual_alias_maps=proxy:mysql:/etc/postfix/mysql_virtual_alias_maps.cf
	postconf -e alias_maps=mysql:/etc/postfix/mysql_virtual_alias_maps.cf

	# Listado de alias desde MySQL
	postconf -e virtual_mailbox_maps=proxy:mysql:/etc/postfix/mysql_virtual_mailbox_maps.cf
	postconf -e virtual_transport=virtual



	############
	#
	# aliases
	#
	############
	echo "root:    ${SERVICE_POSTMASTER}" >> /etc/aliases
	echo "luis:    ${SERVICE_POSTMASTER}" >> /etc/aliases
    /usr/bin/newaliases



	############
	#
	# SASL via SQL
	#
	############

	### 
	### INICIO FICHERO /etc/postfix/sasl/smtpd.conf  
	### ------------------------------------------------------------------------------------------------
	cat > /etc/postfix/sasl/smtpd.conf <<-EOF_SMTPCONF

	pwcheck_method: auxprop
	auxprop_plugin: sql
	sql_engine: mysql
	mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
	sql_hostnames: ${mysqlHost}:${mysqlPort}
	sql_user: ${MAIL_DB_USER}
	sql_passwd: ${MAIL_DB_PASS}
	sql_database: ${MAIL_DB_NAME}
	sql_select: SELECT password FROM mailbox WHERE username='%u@%r' AND active = '1'
	allowanonymouslogin: no
	allowplaintext: yes
	
	EOF_SMTPCONF
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/postfix/sasl/smtpd.conf  
	### 


	############
	#
	# Conexión de Postfix con Mysql
	#
	############

	### 
	### INICIO FICHERO /etc/postfix/mysql_virtual_alias_maps.cf 
	### ------------------------------------------------------------------------------------------------
	cat > /etc/postfix/mysql_virtual_alias_maps.cf <<-EOF_ALIASMAPS
	
	hosts                 = ${mysqlHost}:${mysqlPort}
	user                  = ${MAIL_DB_USER}
	password              = ${MAIL_DB_PASS}
	dbname                = ${MAIL_DB_NAME}
	query                 = SELECT goto FROM alias WHERE address='%s' AND active = '1'
	
	EOF_ALIASMAPS
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/postfix/mysql_virtual_alias_maps.cf  
	### 

	### 
	### INICIO FICHERO /etc/postfix/mysql_virtual_domains_maps.cf 
	### ------------------------------------------------------------------------------------------------
	cat > /etc/postfix/mysql_virtual_domains_maps.cf <<-EOF_DOMAINSMAPS
	
	hosts                 = ${mysqlHost}:${mysqlPort}
	user                  = ${MAIL_DB_USER}
	password              = ${MAIL_DB_PASS}
	dbname                = ${MAIL_DB_NAME}
	query                 = SELECT domain FROM domain WHERE domain='%s' AND active = '1'
	
	EOF_DOMAINSMAPS
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/postfix/mysql_virtual_domains_maps.cf  
	### 
	
	### 
	### INICIO FICHERO /etc/postfix/mysql_virtual_mailbox_maps.cf 
	### ------------------------------------------------------------------------------------------------
	cat > /etc/postfix/mysql_virtual_mailbox_maps.cf <<-EOF_MAILBOXMAPS
	
	hosts                 = ${mysqlHost}:${mysqlPort}
	user                  = ${MAIL_DB_USER}
	password              = ${MAIL_DB_PASS}
	dbname                = ${MAIL_DB_NAME}
	query                 = SELECT maildir FROM mailbox WHERE username='%s' AND active = '1'
	
	EOF_MAILBOXMAPS
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/postfix/mysql_virtual_mailbox_maps.cf  
	### 

	#	
	chmod 640 /etc/postfix/mysql_*.cf
	chgrp postfix /etc/postfix/mysql_*.cf
	
	############
	#
	# Configurar rsyslogd para que envíe logs a un agregador remoto
	#
	############

	### 
	### INICIO FICHERO /etc/rsyslog.conf
	### ------------------------------------------------------------------------------------------------
    cat > /etc/rsyslog.conf <<-EOF_RSYSLOG
    
	\$LocalHostName postfix
	\$ModLoad imuxsock # provides support for local system logging
	#\$ModLoad imklog   # provides kernel logging support
	#\$ModLoad immark  # provides --MARK-- message capability
	
	# provides UDP syslog reception
	#\$ModLoad imudp
	#\$UDPServerRun 514
	
	# provides TCP syslog reception
	#\$ModLoad imtcp
	#\$InputTCPServerRun 514
	
	# Activar para debug interactivo
	#
	#\$DebugFile /var/log/rsyslogdebug.log
	#\$DebugLevel 2
	
	\$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
	
	\$FileOwner root
	\$FileGroup adm
	\$FileCreateMode 0640
	\$DirCreateMode 0755
	\$Umask 0022
	
	#\$WorkDirectory /var/spool/rsyslog
	#\$IncludeConfig /etc/rsyslog.d/*.conf
	
	# Dirección del Host:Puerto agregador de Log's con Fluentd
	#
	*.* @@${fluentdHost}:${fluentdPort}
	
	# Activar para debug interactivo
	#
	#*.* /var/log/syslog
	
	EOF_RSYSLOG
	### ------------------------------------------------------------------------------------------------
	### FIN FICHERO /etc/rsyslog.conf
	### 

	# Re-Confirmo los permisos de /data/vmail
	chown -R vmail:vmail /data/vmail

    #
    # Creo el fichero de control para que el resto de 
    # ejecuciones no realice la primera configuración
    > ${CONFIG_DONE}

fi


##################################################################
#
# EJECUCIÓN DEL COMANDO SOLICITADO
#
##################################################################
#
exec "$@"
