#
# Postfix server base by Luispa, Dec 2014
#
# -----------------------------------------------------
#

# Desde donde parto...
#
FROM debian:jessie

#
MAINTAINER Luis Palacios <luis@luispa.com>

# Pido que el frontend de Debian no sea interactivo
ENV DEBIAN_FRONTEND noninteractive

# Actualizo el sistema operativo e instalo paquetes de software
#
RUN apt-get update && \
    apt-get -y install locales \
                       vim \
                       supervisor \
                       wget \
                       curl 

# Preparo locales
#
RUN locale-gen es_ES.UTF-8
RUN locale-gen en_US.UTF-8
RUN dpkg-reconfigure locales

# Preparo el timezone para Madrid
#
RUN echo "Europe/Madrid" > /etc/timezone; dpkg-reconfigure -f noninteractive tzdata

# Instalo Postfix
#   /etc/aliases
#   /etc/postfix/main.cf
#   /etc/postfix/master.cf
#   postconf
#		
RUN apt-get update && apt-get install -y -q postfix \
											postfix-mysql \
											libsasl2-2 \
											libsasl2-modules \
											libsasl2-modules-sql \
											sasl2-bin \
											opendkim \
											opendkim-tools \
                                            rsyslog \
                                            openssh-server \
                                            tcpdump \
                                            net-tools
                                            
# SSL
#
RUN	openssl req -new -x509 -days 1095 -nodes \
			-out /etc/ssl/certs/postfix.pem  \
			-keyout /etc/ssl/private/postfix.key \
			-subj "/C=ES/ST=Madrid/L=Mi querido pueblo/O=Org/CN=localhost"

# ------- ------- ------- ------- ------- ------- -------
# DEBUG ( Descomentar durante debug del contenedor )
# ------- ------- ------- ------- ------- ------- -------
#
# Herramientas SSH, tcpdump y net-tools
#RUN apt-get update && \
#    apt-get -y install 	openssh-server \
#                       	tcpdump \
#                        net-tools
## Setup de SSHD
#RUN mkdir /var/run/sshd
#RUN echo 'root:docker' | chpasswd
#RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
#RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
#ENV NOTVISIBLE "in users profile"
#RUN echo "export VISIBLE=now" >> /etc/profile

## Script que uso a menudo durante las pruebas. Es como "cat" pero elimina líneas de comentarios
RUN echo "grep -vh '^[[:space:]]*#' \"\$@\" | grep -v '^//' | grep -v '^;' | grep -v '^\$' | grep -v '^\!' | grep -v '^--'" > /usr/bin/confcat
RUN chmod 755 /usr/bin/confcat

#-----------------------------------------------------------------------------------

# Ejecutar siempre al arrancar el contenedor este script
#
ADD do.sh /do.sh
RUN chmod +x /do.sh
ENTRYPOINT ["/do.sh"]

#
# Si no se especifica nada se ejecutará lo siguiente: 
#
CMD ["/usr/bin/supervisord", "-n -c /etc/supervisor/supervisord.conf"]

