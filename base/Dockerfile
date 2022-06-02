FROM krallin/centos-tini:7
ENV MUNGE_UID=981 \
  SLURM_UID=982 \
  WORKER_UID=1000

RUN groupadd -g $MUNGE_UID munge \
  && useradd  -m -c "MUNGE Uid 'N' Gid Emporium" -d /var/lib/munge -u $MUNGE_UID -g munge  -s /sbin/nologin munge \
  && groupadd -g $SLURM_UID slurm \
  && useradd  -m -c "Slurm workload manager" -d /var/lib/slurm -u $SLURM_UID -g slurm  -s /bin/bash slurm \
  && groupadd -g $WORKER_UID worker \
  && useradd  -m -c "Workflow user" -d /home/worker -u $WORKER_UID -g worker  -s /bin/bash worker

RUN yum -y install epel-release && \
    yum -y install sudo wget which git vim tree openssh-server openssh-clients net-tools

COPY rpms /packages
WORKDIR /packages
RUN yum -y localinstall $(ls | grep 'munge') && yum -y localinstall $(ls | grep -v -e 'torque' -e 'openmpi') && \
    git clone https://github.com/fortis931w/slurm-singularity-exec.git && cd slurm-singularity-exec && \
    mkdir -p /etc/slurm/spank && source scl_source enable devtoolset-11 && make singularity-exec.so && \
    make install 

VOLUME ["/storage","/.secret"]
WORKDIR /
EXPOSE 22 6817 6818