FROM slurm.base

RUN yum -y install gcc-c++ gcc-gfortran mariadb-server mariadb-devel && \
    yum -y localinstall /packages/openmpi-*.rpm && \
    rm -f /packages/slurm-*.rpm /packages/openmpi-*.rpm \
    && yum clean all \
    && rm -rf /var/cache/yum 


ENV CLUSTER_NAME=magi \
    CONTROL_MACHINE=balthasar \
    PARTITION_NAME=docker \
    DATABASE_HOST=balthasar.magi 

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/usr/local/bin/tini", "--", "/entrypoint.sh"]
