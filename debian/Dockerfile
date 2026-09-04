FROM debian:13

ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive

# 1. Installation des paquets nécessaires et nettoyage Systemd
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install -y --no-install-recommends openssh-server systemd sudo passwd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*;\
    rm -f /etc/systemd/system/*.wants/*;\
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*;\
    rm -f /lib/systemd/system/anaconda.target.wants/*;

# 2. Configuration SSH (Création du dossier requis et fix PAM)
RUN mkdir -p /var/run/sshd && \
    sed -i 's/.*pam_nologin.so/#&/' /etc/pam.d/sshd && \
    rm -f /var/run/nologin /etc/nologin

# 3. Activation du service SSH via systemd
RUN systemctl enable ssh.service

EXPOSE 22
VOLUME [ "/sys/fs/cgroup" ]

CMD ["/lib/systemd/systemd"]