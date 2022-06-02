#!/usr/bin/env bash
set -e

wget --tries=5 https://github.com/dun/munge/releases/download/munge-0.5.14/munge-0.5.14.tar.xz
wget --tries=5 https://github.com/dun.gpg
wget --tries=5 https://github.com/dun/munge/releases/download/munge-0.5.14/munge-0.5.14.tar.xz.asc
rpmbuild -tb munge-0.5.14.tar.xz
cp /root/rpmbuild/RPMS/x86_64/munge-* /packages

wget --tries=5 https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2
rpmbuild -ta "slurm-${SLURM_VERSION}.tar.bz2"
cp /root/rpmbuild/RPMS/x86_64/slurm* /packages

wget --tries=5 https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OPENMPI_VERSION}.tar.bz2
curl https://raw.githubusercontent.com/open-mpi/ompi/main/contrib/dist/linux/buildrpm.sh -o buildrpm.sh
chmod +x buildrpm.sh
yum -y localinstall /root/rpmbuild/RPMS/x86_64/slurm-*
mkdir -p /usr/src/redhat
cd /usr/src/redhat
ln -s /root/rpmbuild/SOURCES SOURCES
ln -s /root/rpmbuild/RPMS RPMS
ln -s /root/rpmbuild/SRPMS SRPMS
ln -s /root/rpmbuild/SPECS SPECS
cd -
./buildrpm.sh -b -s -c --with-slurm -c --with-pmi openmpi-${OPENMPI_VERSION}.tar.bz2
cp /root/rpmbuild/RPMS/x86_64/openmpi-* /packages
cd /packages
wget --tries=5 https://github.com/sylabs/singularity/releases/download/v3.10.0/singularity-ce-3.10.0-1.el7.x86_64.rpm

exec "$@"
