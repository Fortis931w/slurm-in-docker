#!/bin/bash

for mnt in "$@"; do
  if [[ ! "$mnt" =~ ^/storage/ ]]; then
    >&2 echo "Path to NFS export must be inside of the \"/storage/\" directory"
    exit 1
  fi
  mkdir -p $mnt
  chmod 777 $mnt
done

exportfs -a
rpcbind
rpc.statd
rpc.nfsd

exec rpc.mountd --foreground