#!/usr/bin/env bash
set -e

# start sshd server
_sshd_host() {
  if [ ! -d /var/run/sshd ]; then
    mkdir /var/run/sshd
    ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' > /dev/null
    ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N '' > /dev/null
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' > /dev/null
  fi
  /usr/sbin/sshd
}

# start munge using existing key
_munge_start_using_key() {
  if [ -f /run/munge/munge.socket.2 ];then
    pkill -9 munged
  fi
  if [ ! -f /.secret/munge.key ]; then
    echo -n "checking for munge.key"
    while [ ! -f /.secret/munge.key ]; do
      echo -n "."
      sleep 1
    done
    echo ""
  fi
  if [ ! -d /run/munge ]; then
    mkdir /run/munge -p
  fi
  yes | cp /.secret/munge.key /etc/munge/munge.key
  chown -R munge: /etc/munge /var/lib/munge /var/log/munge /run/munge
  chmod 0700 /etc/munge
  chmod 0711 /var/lib/munge
  chmod 0700 /var/log/munge
  chmod 0755 /run/munge
  sudo -u munge /sbin/munged
  munge -n
  munge -n | unmunge
  remunge
}

# wait for worker user in shared /home volume
_wait_for_worker() {
  if [ ! -f /home/worker/.ssh/id_rsa.pub ]; then
    echo -n "cheking for id_rsa.pub"
    while [ ! -f /home/worker/.ssh/id_rsa.pub ]; do
      echo -n "."
      sleep 1
    done
    echo ""
  fi
}

# run slurmd configless
_slurmd() {
  mkdir -p /var/spool/slurm/d
  chown slurm: /var/spool/slurm/d
  touch /var/log/slurmd.log
  chown slurm: /var/log/slurmd.log
  /usr/sbin/slurmd --conf-server balthasar:6817
}

### main ###
_sshd_host
_munge_start_using_key
_wait_for_worker
_slurmd

tail -f /dev/null
