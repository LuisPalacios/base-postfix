# Introducción

Este repositorio alberga un *contenedor Docker* para montar Postfix, está automatizado en el Registry Hub de Docker [luispa/base-postfix](https://registry.hub.docker.com/u/luispa/base-postfix/) conectado con el proyecto en [GitHub base-postfix](https://github.com/LuisPalacios/base-postfix)


## Ficheros

* **Dockerfile**: Para crear la base de un servicio Postfix

## Instalación de la imagen

Para usar la imagen desde el registry de docker hub

    totobo ~ $ docker pull luispa/base-postfix


## Clonar el repositorio

Si quieres clonar el repositorio lo encontrarás en Github, este es el comando poder trabajar con él directamente

    ~ $ clone https://github.com/LuisPalacios/docker-postfix.git

Luego puedes crear la imagen localmente con el siguiente comando

    $ docker build -t luispa/base-postfix ./


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
