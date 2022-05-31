FROM centos:7

ENV SLURM_VERSION=21.08.8-2 \
    OPENMPI_VERSION=4.1.4

RUN sed -e 's|^mirrorlist=|#mirrorlist=|g' \
         -e 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.shanghaitech.edu.cn|g' \
         -i.bak \
         /etc/yum.repos.d/CentOS-*.repo && \
    sed  -i '2c enabled=0' /etc/yum/pluginconf.d/fastestmirror.conf && yum -y install deltarpm epel-release && \
    yum -y install which   wget   munge   munge-libs   munge-devel   rpm-build   gcc   git   openssl   openssl-devel   libssh2-devel   pam-devel   numactl   numactl-devel   hwloc   hwloc-devel   lua   lua-devel   readline-devel   rrdtool-devel   ncurses-devel   gtk2-devel   man2html   libibmad   libibumad   perl-Switch   perl-ExtUtils-MakeMaker   mariadb-server   mariadb-devel   python3 bzip2-devel && \
    yum -y group install "Development Tools"
COPY entrypoint.sh /entrypoint.sh
VOLUME ["/packages"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ls", "-alh", "/packages"]
