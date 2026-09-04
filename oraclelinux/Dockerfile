FROM oraclelinux:10

ENV container=docker

# 1. Installation des paquets nécessaires
RUN dnf -y upgrade && \
    dnf -y install openssh-server passwd systemd sudo && \
    dnf clean all && \
    rm -rf /var/cache/yum /var/cache/dnf /var/log/dnf* /var/log/yum.* && \
    (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
    rm -f /lib/systemd/system/multi-user.target.wants/*;\
    rm -f /etc/systemd/system/*.wants/*;\
    rm -f /lib/systemd/system/local-fs.target.wants/*; \
    rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
    rm -f /lib/systemd/system/basic.target.wants/*;\
    rm -f /lib/systemd/system/anaconda.target.wants/*;

# 3. FIX : Désactivation de pam_nologin et nettoyage des fichiers /etc/nologin
RUN sed -i 's/.*pam_nologin.so/#&/' /etc/pam.d/sshd && \
    rm -f /var/run/nologin /etc/nologin

# 4. Définir la cible par défaut sur multi-user (au lieu de Graphical Interface)
RUN systemctl set-default multi-user.target && \
    systemctl enable sshd.service

EXPOSE 22
VOLUME [ "/sys/fs/cgroup" ]

CMD ["/usr/sbin/init"]