FROM krallin/centos-tini:7

RUN sed -e 's|^mirrorlist=|#mirrorlist=|g' \
         -e 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.shanghaitech.edu.cn|g' \
         -i.bak \
         /etc/yum.repos.d/CentOS-*.repo && \
    sed  -i '2c enabled=0' /etc/yum/pluginconf.d/fastestmirror.conf && \
    yum -y install nfs-utils && \
    echo '/storage *(insecure,rw,sync,no_root_squash,fsid=0)' > /etc/exports && \
    yum clean all

COPY entrypoint.sh /entrypoint.sh

VOLUME ["/storage"]
EXPOSE 111/udp 2049/tcp

ENTRYPOINT ["/usr/local/bin/tini", "--", "/entrypoint.sh"]
