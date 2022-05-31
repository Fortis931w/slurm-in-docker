FROM slurm.base

RUN yum -y install gcc-c++ gcc-gfortran && \
    yum -y localinstall /packages/openmpi-*.rpm && \
    rm -f /packages/slurm-*.rpm /packages/openmpi-*.rpm \
    && yum clean all \
    && rm -rf /var/cache/yum 

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/usr/local/bin/tini", "--", "/entrypoint.sh"]
