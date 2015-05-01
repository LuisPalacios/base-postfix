# Introducción

Este repositorio alberga un *contenedor Docker* para montar Postfix, está automatizado en el Registry Hub de Docker [luispa/base-postfix](https://registry.hub.docker.com/u/luispa/base-postfix/) conectado con el proyecto en [GitHub base-postfix](https://github.com/LuisPalacios/base-postfix)

Tengo otro repositorio [servicio-correo](https://github.com/LuisPalacios/servicio-correo) donde verás un ejemplo de uso. Además te recomiendo que consultes este [apunte técnico sobre varios servicios en contenedores Docker](http://www.luispa.com/?p=172) para tener una visión más global de otros contenedores Docker y fuentes en GitHub y entender mejor este ejemplo.

## Ficheros

* **Dockerfile**: Para crear la base de servicio.
* **do.sh**: Para arrancar el contenedor creado con esta imagen.

## Instalación de la imagen

Para usar la imagen desde el registry de docker hub

    totobo ~ $ docker pull luispa/base-postfix


## Clonar el repositorio

Si quieres clonar el repositorio lo encontrarás en Github, este es el comando poder trabajar con él directamente

    ~ $ clone https://github.com/LuisPalacios/docker-postfix.git

Luego puedes crear la imagen localmente con el siguiente comando

    $ docker build -t luispa/base-postfix ./


# Revisar y personalizar

Es muy importante que revises el fichero **do.sh** para comprobar que la configuración que se realiza es adecuada para tus intereses. 

Un ejemplo son las direcciones que acepto en el el fichero master.cf y main.cf que se configura automáticamente. Acepto todas las IP's de la intranet, me refiero a estas líneas:

	#####################
    #
    # postfix / master.cf ((-vvv al final para activar debug, quitar en la versión final))
    #
	#####################
	#
	:
	postconf -P 10025/inet/mynetworks="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16"
	:

	#####################
    #
    # postfix / main.cf 
    #
	#####################
	#
	:
	postconf -e mynetworks="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8"
	:

Puede darse el caso en el que no te convenga usar estas IP's y si es así te recomiendo que clones el repositorio (punto anterior) y lo adaptes a tus necesidades. 

### Volumen

Directorio persistente para configurar el Timezone. Crear el directorio /Apps/data/tz y dentro de él crear el fichero timezone. Luego montarlo con -v o con fig.yml

    Montar:
       "/Apps/data/tz:/config/tz"  
    Preparar: 
       $ echo "Europe/Madrid" > /config/tz/timezone


# Pruebas

Para comprobar que el contendor funciona correctametne dejo aquí algunos comandos a modo de ejemplo para hacer troubleshooting.

- Comprobar la autenticación del servidor SMTP con postfix, sasl y mysql.

	    $ echo -ne '\000prueba@parchis.org\000my_pass' | openssl base64
   	 	AHBydWViYUBwYXJjaGlzLm9yZwBteV9wYXNz
    	
    	$ telnet server.parchis.org 25
	    EHLO parchis.org
    	250-server.parchis.org
    	250-PIPELINING
    	250-SIZE 10240000
    	250-VRFY
    	250-ETRN
    	250-STARTTLS
    	250-AUTH PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
    	250-AUTH=PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
    	250-ENHANCEDSTATUSCODES
    	250-8BITMIME
    	250 DSN
		
    	AUTH PLAIN AHBydWViYUBwYXJjaGlzLm9yZwBteV9wYXNz
    	235 2.7.0 Authentication successful
