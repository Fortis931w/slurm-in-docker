#!/usr/bin/env bash
set -e
SLURM_ACCT_DB_SQL=/slurm_acct_db.sql

_slurm_acct_db() {
  {
    echo "create database slurm_acct_db;"
    echo "create user 'slurm'@'${DATABASE_HOST}';"
    echo "set password for 'slurm'@'${DATABASE_HOST}' = password('/run/munge/munge.socket.2');"
    echo "grant usage on *.* to 'slurm'@'${DATABASE_HOST}';"
    echo "grant all privileges on slurm_acct_db.* to 'slurm'@'${DATABASE_HOST}';"
    echo "flush privileges;"
  } >> $SLURM_ACCT_DB_SQL
}

_mariadb_start() {
  # mariadb somehow expects `resolveip` to be found under this path; see https://github.com/SciDAS/slurm-in-docker/issues/26
  if [ ! -f /usr/bin/resolveip ]; then
    ln -s /usr/bin/resolveip /usr/libexec/resolveip
  fi
  if [ ! -f /var/lock/mariabd.lock ]; then
    mysql_install_db
    chown -R mysql: /var/lib/mysql/ /var/log/mariadb/ /var/run/mariadb
    cd /var/lib/mysql
    mysqld_safe --user=mysql &
    cd /
    _slurm_acct_db
    sleep 5s
    mysql -uroot < $SLURM_ACCT_DB_SQL
    touch touch "/var/lock/mariabd.lock"
    else
    echo "restart"
  fi
}

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

# setup worker ssh to be passwordless
_ssh_worker() {
  if [[ ! -d /home/worker ]]; then
    mkdir -p /home/worker
    chown -R worker:worker /home/worker
  fi
  cat > /home/worker/setup-worker-ssh.sh <<'EOF2'
mkdir -p ~/.ssh
chmod 0700 ~/.ssh
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N "" -C "$(whoami)@$(hostname)-$(date -I)"
fi
cat ~/.ssh/id_rsa.pub > ~/.ssh/authorized_keys
chmod 0640 ~/.ssh/authorized_keys
cat >> ~/.ssh/config <<EOF
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel QUIET
EOF
chmod 0644 ~/.ssh/config
cd ~/
tar -czvf ~/worker-secret.tar.gz .ssh
cd -
EOF2
  chmod +x /home/worker/setup-worker-ssh.sh
  chown worker: /home/worker/setup-worker-ssh.sh
  sudo -u worker /home/worker/setup-worker-ssh.sh
}

# start munge and generate key
_munge_start() {
  if [ ! -d /run/munge ]; then
    mkdir /run/munge -p
  fi
  if [ ! -f /var/lock/mungekey.lock ]; then
    mungekey -c -f
    touch /var/lock/mungekey.lock
  fi
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

# copy secrets to /.secret directory for other nodes
_copy_secrets() {
  yes | cp -r /home/worker/.ssh /root/
  yes | cp -r /home/worker/worker-secret.tar.gz /.secret/worker-secret.tar.gz
  yes | cp -r /home/worker/setup-worker-ssh.sh /.secret/setup-worker-ssh.sh
  yes | cp -r /etc/munge/munge.key /.secret/munge.key
  rm -f /home/worker/worker-secret.tar.gz
  rm -f /home/worker/setup-worker-ssh.sh
}

# generate slurm.conf
_generate_slurm_conf() {
  cat > /etc/slurm/slurm.conf <<EOF
# Cluster Name：集群名
 ClusterName=${CLUSTER_NAME} # 集群名，任意英文和数字名字

# Control Machines：Slurmctld控制进程节点
 SlurmctldHost=${CONTROL_MACHINE} # 启动slurmctld进程的节点名，如这里的admin
 #BackupController=   # 冗余备份节点，可空着
 SlurmctldParameters=enable_configless # 采用无配置模式

 # Slurm User：Slurm用户
 SlurmUser=slurm # slurmctld启动时采用的用户名

 # Slurm Port Numbers：Slurm服务通信端口
 SlurmctldPort=6817 # Slurmctld服务端口，设为6817，如不设置，默认为6817号端口
 SlurmdPort=6818    # Slurmd服务端口，设为6818，如不设置，默认为6818号端口

 # State Preservation：状态保持
 StateSaveLocation=/var/spool/slurm/ctld # 存储slurmctld服务状态的目录，如有备份控制节点，则需要所有SlurmctldHost节点都能共享读写该目录
 SlurmdSpoolDir=/var/spool/slurmd # Slurmd服务所需要的目录，为各节点各自私有目录，不得多个slurmd节点共享

 ReturnToService=1 #设定当DOWN（失去响应）状态节点如何恢复服务，默认为0。
     # 0: 节点状态保持DOWN状态，只有当管理员明确使其恢复服务时才恢复
     # 1: 仅当由于无响应而将DOWN节点设置为DOWN状态时，才可以当有效配置注册后使DOWN节点恢复服务。如节点由于任何其它原因（内存不足、意外重启等）被设置为DOWN，其状态将不会自动更改。当节点的内存、GRES、CPU计数等等于或大于slurm.conf中配置的值时，该节点才注册为有效配置。
     # 2: 使用有效配置注册后，DOWN节点将可供使用。该节点可能因任何原因被设置为DOWN状态。当节点的内存、GRES、CPU计数等等于或大于slurm.conf 中配置的值，该节点才注册为有效配置。￼

 # Default MPI Type：默认MPI类型
 MPIDefault=none
     # MPI-PMI2: 对支持PMI2的MPI实现
     # MPI-PMIx: Exascale PMI实现
     # None: 对于大多数其它MPI，建议设置

 # Process Tracking：进程追踪，定义用于确定特定的作业所对应的进程的算法，它使用信号、杀死和记账与作业步相关联的进程
 ProctrackType=proctrack/pgid
     # Cgroup: 采用Linux cgroup来生成作业容器并追踪进程，需要设定/etc/slurm/cgroup.conf文件
     # Cray XC: 采用Cray XC专有进程追踪
     # LinuxProc: 采用父进程IP记录，进程可以脱离Slurm控制
     # Pgid: 采用Unix进程组ID(Process Group ID)，进程如改变了其进程组ID则可以脱离Slurm控制

 # Scheduling：调度
 # DefMemPerCPU=0 # 默认每颗CPU可用内存，以MB为单位，0为不限制。如果将单个处理器分配给作业（SelectType=select/cons_res 或 SelectType=select/cons_tres），通常会使用DefMemPerCPU
 # MaxMemPerCPU=0 # 最大每颗CPU可用内存，以MB为单位，0为不限制。如果将单个处理器分配给作业（SelectType=select/cons_res 或 SelectType=select/cons_tres），通常会使用MaxMemPerCPU
 # SchedulerTimeSlice=30 # 当GANG调度启用时的时间片长度，以秒为单位
 SchedulerType=sched/backfill # 要使用的调度程序的类型。注意，slurmctld守护程序必须重新启动才能使调度程序类型的更改生效（重新配置正在运行的守护程序对此参数无效）。如果需要，可以使用scontrol命令手动更改作业优先级。可接受的类型为：
     # sched/backfill # 用于回填调度模块以增加默认FIFO调度。如这样做不会延迟任何较高优先级作业的预期启动时间，则回填调度将启动较低优先级作业。回填调度的有效性取决于用户指定的作业时间限制，否则所有作业将具有相同的时间限制，并且回填是不可能的。注意上面SchedulerParameters选项的文档。这是默认配置
     # sched/builtin # 按优先级顺序启动作业的FIFO调度程序。如队列中的任何作业无法调度，则不会调度该队列中优先级较低的作业。对于作业的一个例外是由于队列限制（如时间限制）或关闭/耗尽节点而无法运行。在这种情况下，可以启动较低优先级的作业，而不会影响较高优先级的作业。
     # sched/hold # 如果 /etc/slurm.hold 文件存在，则暂停所有新提交的作业，否则使用内置的FIFO调度程序。

 # Resource Selection：资源选择，定义作业资源（节点）选择算法
 SelectType=select/cons_tres
     # select/cons_tres: 单个的CPU核、内存、GPU及其它可追踪资源作为可消费资源（消费及分配），建议设置
     # select/cons_res: 单个的CPU核和内存作为可消费资源
     # select/cray_aries: 对于Cray系统
     # select/linear: 基于主机的作为可消费资源，不管理单个CPU等的分配

 # SelectTypeParameters：资源选择类型参数，当SelectType=select/linear时仅支持CR_ONE_TASK_PER_CORE和CR_Memory；当SelectType=select/cons_res、SelectType=select/cray_aries和SelectType=select/cons_tres时，默认采用CR_Core_Memory
 SelectTypeParameters=CR_Core_Memory
     # CR_CPU: CPU核数作为可消费资源
     # CR_Socket: 整颗CPU作为可消费资源
     # CR_Core: CPU核作为可消费资源，默认
     # CR_Memory: 内存作为可消费资源，CR_Memory假定MaxShare大于等于1
     # CR_CPU_Memory: CPU和内存作为可消费资源
     # CR_Socket_Memory: 整颗CPU和内存作为可消费资源
     # CR_Core_Memory: CPU和和内存作为可消费资源

 # Task Launch：任务启动
 TaskPlugin=task/cgroup,task/affinity #设定任务启动插件。可被用于提供节点内的资源管理（如绑定任务到特定处理器），TaskPlugin值可为:
     # task/affinity: CPU亲和支持（man srun查看其中--cpu-bind、--mem-bind和-E选项）
     # task/cgroup: 强制采用Linux控制组cgroup分配资源（man group.conf查看帮助）
     # task/none: #无任务启动动作

 # Prolog and Epilog：前处理及后处理
 # Prolog/Epilog: 完整的绝对路径，在用户作业开始前(Prolog)或结束后(Epilog)在其每个运行节点上都采用root用户执行，可用于初始化某些参数、清理作业运行后的可删除文件等
 # Prolog=/opt/bin/prolog.sh # 作业开始运行前需要执行的文件，采用root用户执行
 # Epilog=/opt/bin/epilog.sh # 作业结束运行后需要执行的文件，采用root用户执行

 # SrunProlog/Epilog # 完整的绝对路径，在用户作业步开始前(SrunProlog)或结束后(Epilog)在其每个运行节点上都被srun执行，这些参数可以被srun的--prolog和--epilog选项覆盖
 # SrunProlog=/opt/bin/srunprolog.sh # 在srun作业开始运行前需要执行的文件，采用运行srun命令的用户执行
 # SrunEpilog=/opt/bin/srunepilog.sh # 在srun作业结束运行后需要执行的文件，采用运行srun命令的用户执行

 # TaskProlog/Epilog: 绝对路径，在用户任务开始前(Prolog)和结束后(Epilog)在其每个运行节点上都采用运行作业的用户身份执行
 # TaskProlog=/opt/bin/taskprolog.sh # 作业开始运行前需要执行的文件，采用运行作业的用户执行
 # TaskEpilog=/opt/bin/taskepilog.sh # 作业结束后需要执行的文件，采用运行作业的用户执行行

 # 顺序：
    # 1. pre_launch_priv()：TaskPlugin内部函数
    # 2. pre_launch()：TaskPlugin内部函数
    # 3. TaskProlog：slurm.conf中定义的系统范围每个任务
    # 4. User prolog：作业步指定的，采用srun命令的--task-prolog参数或SLURM_TASK_PROLOG环境变量指定
    # 5. Task：作业步任务中执行
    # 6. User epilog：作业步指定的，采用srun命令的--task-epilog参数或SLURM_TASK_EPILOG环境变量指定
    # 7. TaskEpilog：slurm.conf中定义的系统范围每个任务
    # 8. post_term()：TaskPlugin内部函数

 # Event Logging：事件记录
 # Slurmctld和slurmd守护进程可以配置为采用不同级别的详细度记录，从0（不记录）到7（极度详细）
 SlurmctldDebug=info # 默认为info
 SlurmctldLogFile=/var/log/slurmctld.log # 如是空白，则记录到syslog
 SlurmdDebug=info # 默认为info
 SlurmdLogFile=/var/log/slurmd.log # 如为空白，则记录到syslog，如名字中的有字符串"%h"，则"%h"将被替换为节点名

 # Job Completion Logging：作业完成记录
 JobCompType=jobcomp/filetxt
 # 指定作业完成是采用的记录机制，默认为None，可为以下值之一:
    # None: 不记录作业完成信息
    # Elasticsearch: 将作业完成信息记录到Elasticsearch服务器
    # FileTxt: 将作业完成信息记录在一个纯文本文件中
    # Lua: 利用名为jobcomp.lua的文件记录作业完成信息
    # Script: 采用任意脚本对原始作业完成信息进行处理后记录
    # MySQL: 将完成状态写入MySQL或MariaDB数据库

 JobCompLoc=/var/log/slurm/job_completions
 #JobCompType=filetxt # 设定记录作业完成信息的文本文件位置（若JobCompType=filetxt），或将要运行的脚本（若JobCompType=script），或Elasticsearch服务器的URL（若JobCompType=elasticsearch），或数据库名字（JobCompType为其它值时）

 # 设定数据库在哪里运行，且如何连接
 #JobCompHost=${DATABASE_HOST} # 存储作业完成信息的数据库主机名
 # JobCompPort= # 存储作业完成信息的数据库服务器监听端口
 #JobCompUser=slurm # 用于与存储作业完成信息数据库进行对话的用户名
 #JobCompPass=/run/munge/munge.socket.2 # 用于与存储作业完成信息数据库进行对话的用户密码

 # Job Accounting Gather：作业记账收集
 JobAcctGatherType=jobacct_gather/none # Slurm记录每个作业消耗的资源，JobAcctGatherType值可为以下之一：
    # jobacct_gather/none: 不对作业记账
    # jobacct_gather/cgroup: 收集Linux cgroup信息
    # jobacct_gather/linux: 收集Linux进程表信息，建议
 JobAcctGatherFrequency=30 # 设定轮寻间隔，以秒为单位。若为-，则禁止周期性抽样

 # Job Accounting Storage：作业记账存储
 AccountingStorageType=accounting_storage/slurmdbd # 与作业记账收集一起，Slurm可以采用不同风格存储可以以许多不同的方式存储会计信息，可为以下值之一：
     # accounting_storage/none: 不记录记账信息
     # accounting_storage/slurmdbd: 将作业记账信息写入Slurm DBD数据库
 #AccountingStorageLoc=/var/log/slurm/accountingand/ 
#设定文件位置或数据库名，为完整绝对路径或为数据库的数据库名，当采用slurmdb时默认为slurm_acct_db

 # 设定记账数据库信息，及如何连接
 AccountingStorageHost=${DATABASE_HOST} # 记账数据库主机名
 AccountingStoragePort=6819 # 记账数据库服务监听端口
 AccountingStorageUser=slurm # 记账数据库用户名
 AccountingStoragePass=/run/munge/munge.socket.2 # 记账数据库用户密码。对于SlurmDBD，这是一个替代套接字socket名，用于Munge守护进程，提供企业范围的身份验证
 # AccountingStoreFlags= # 以逗号（,）分割的列表。选项是：
     # job_comment：在数据库中存储作业说明域
     # job_script：在数据库中存储脚本
     # job_env：存储批处理作业的环境变量
 # AccountingStorageTRES=gres/gpu # 设置GPU时需要
 # GresTypes=gpu # 设置GPU时需要

 # Process ID Logging：进程ID记录，定义记录守护进程的进程ID的位置
 SlurmctldPidFile=/var/run/slurmctld.pid # 存储slurmctld进程号PID的文件
 SlurmdPidFile=/var/run/slurmd.pid # 存储slurmd进程号PID的文件

 # Timers：定时器
 SlurmctldTimeout=120 # 设定备份控制器在主控制器等待多少秒后成为激活的控制器
 SlurmdTimeout=300 # Slurm控制器等待slurmd未响应请求多少秒后将该节点状态设置为DOWN
 InactiveLimit=0 # 潜伏期控制器等待srun命令响应多少秒后，将在考虑作业或作业步骤不活动并终止它之前。0表示无限长等待
 MinJobAge=300 # Slurm控制器在等待作业结束多少秒后清理其记录
 KillWait=30 # 在作业到达其时间限制前等待多少秒后在发送SIGKILLL信号之前发送TERM信号以优雅地终止
 WaitTime=0 # 在一个作业步的第一个任务结束后等待多少秒后结束所有其它任务，0表示无限长等待

 # Compute Machines：计算节点
 NodeName=casper[01-03] RealMemory=1800 CPUs=1 State=UNKNOWN
 # NodeName=gnode[01-10] Gres=gpu:v100:2 CPUs=40 RealMemory=385560 Sockets=2 CoresPerSocket=20 ThreadsPerCore=1 State=UNKNOWN #GPU节点例子，主要为Gres=gpu:v100:2
     # NodeName=node[1-10] # 计算节点名，node[1-10]表示为从node1、node2连续编号到node10，其余类似
     # NodeAddr=192.168.1.[1-10] # 计算节点IP
     # CPUs=48 # 节点内CPU核数，如开着超线程，则按照2倍核数计算，其值为：Sockets*CoresPerSocket*ThreadsPerCore
     # RealMemory=192000 # 节点内作业可用内存数(MB)，一般不大于free -m的输出，当启用select/cons_res插件限制内存时使用
     # Sockets=2 # 节点内CPU颗数
     # CoresPerSocket=24 # 每颗CPU核数
     # ThreadsPerCore=1 # 每核逻辑线程数，如开了超线程，则为2
     # State=UNKNOWN # 状态，是否启用，State可以为以下之一：
         # CLOUD   # 在云上存在
         # DOWN    # 节点失效，不能分配给在作业
         # DRAIN   # 节点不能分配给作业
         # FAIL    # 节点即将失效，不能接受分配新作业
         # FAILING # 节点即将失效，但上面有作业未完成，不能接收新作业
         # FUTURE  # 节点为了将来使用，当Slurm守护进程启动时设置为不存在，可以之后采用scontrol命令简单地改变其状态，而不是需要重启slurmctld守护进程。当这些节点有效后，修改slurm.conf中它们的State。在它们被设置为有效前，采用Slurm看不到它们，也尝试与其联系。
               # 动态未来节点(Dynamic Future Nodes)：
                  # slurmd启动时如有-F[<feature>]参数，将关联到一个与slurmd -C命令显示配置(sockets、cores、threads)相同的配置的FUTURE节点。节点的NodeAddr和NodeHostname从slurmd守护进程自动获取，并且当被设置为FUTURE状态后自动清除。动态未来节点在重启时保持non-FUTURE状态。利用scontrol可以将其设置为FUTURE状态。
                  # 若NodeName与slurmd的HostName映射未通过DNS更新，动态未来节点不知道在之间如何进行通信，其原因在于NodeAddr和NodeHostName未在slurm.conf被定义，而且扇出通信(fanout communication)需要通过将TreeWidth设置为一个较高的数字（如65533）来使其无效。若做了DNS映射，则可以使用cloud_dns SlurmctldParameter。
          # UNKNOWN # 节点状态未被定义，但将在节点上启动slurmd进程后设置为BUSY或IDLE，该为默认值。

 PartitionName=${PARTITION_NAME} Nodes=ALL Default=YES MaxTime=INFINITE State=UP
     # PartitionName=batch # 队列分区名
     # Nodes=node[1-10] # 节点名
     # Default=Yes # 作为默认队列，运行作业不知明队列名时采用的队列
     # MaxTime=INFINITE # 作业最大运行时间，以分钟为单位，INFINITE表示为无限制
     # State=UP # 状态，是否启用
     # Gres=gpu:v100:2 # 设置节点有两块v100 GPU卡，需要在GPU节点 /etc/slum/gres.conf 文件中有类似下面配置：
         #AutoDetect=nvml
         #Name=gpu Type=v100 File=/dev/nvidia[0-1] #设置资源的名称Name是gpu，类型Type为v100，名称与类型可以任意取，但需要与其它方面配置对应，File=/dev/nvidia[0-1]指明了使用的GPU设备。
         #Name=mps Count=100
EOF
}

# generate slurmdbd.conf
_generate_slurmdbd_conf() {
cat>/etc/slurm/slurmdbd.conf<<EOF
#
# Example slurmdbd.conf file.
#
# See the slurmdbd.conf man page for more information.
#
# Archive info
#ArchiveJobs=yes
#ArchiveDir="/tmp"
#ArchiveSteps=yes
#ArchiveScript=
#JobPurge=12
#StepPurge=1
#
# Authentication info
AuthType=auth/munge
AuthInfo=/run/munge/munge.socket.2
#
# slurmDBD info
DbdAddr=${DATABASE_HOST}
DbdHost=${DATABASE_HOST}
DbdPort=6819
SlurmUser=slurm
#MessageTimeout=300
DebugLevel=4
#DefaultQOS=normal,standby
LogFile=/var/log/slurmdbd.log
PidFile=/var/run/slurmdbd.pid
#PluginDir=/usr/lib/slurm
#PrivateData=accounts,users,usage,jobs
#TrackWCKey=yes
#
# Database info
StorageType=accounting_storage/mysql
StorageHost=${DATABASE_HOST}
StoragePort=3306
StoragePass=/run/munge/munge.socket.2
StorageUser=slurm
StorageLoc=slurm_acct_db
EOF

chown slurm:slurm /etc/slurm/slurmdbd.conf
chmod 600 /etc/slurm/slurmdbd.conf
}

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

_slurmdbd() {
  mkdir -p /etc/mysql
  cat>/etc/mysql/my.cnf<<EOF
  [mysqld]
 innodb_buffer_pool_size=1024M
 innodb_log_file_size=64M
 innodb_lock_wait_timeout=900
EOF
  _mariadb_start
  mkdir -p /var/spool/slurm/d \
    /var/log/slurm
  chown slurm: /var/spool/slurm/d \
    /var/log/slurm
  if [[ ! -f /home/config/slurmdbd.conf ]]; then
    echo "### generate slurmdbd.conf ###"
    _generate_slurmdbd_conf
  else
    echo "### use provided slurmdbd.conf ###"
    cp /home/config/slurmdbd.conf /etc/slurm/slurmdbd.conf
  fi
  /usr/sbin/slurmdbd
  cp /etc/slurm/slurmdbd.conf /.secret/slurmdbd.conf
}

_slurmctld() {
  mkdir -p /var/spool/slurm/ctld /var/spool/slurmd
  chown -R slurm: /var/spool/slurm/ctld  /var/spool/slurmd
  touch /var/log/slurmctld.log
  chown slurm: /var/log/slurmctld.log
  if [[ ! -f /home/config/slurm.conf ]]; then
    echo "### generate slurm.conf ###"
    _generate_slurm_conf
  else
    echo "### use provided slurm.conf ###"
    cp /home/config/slurm.conf /etc/slurm/slurm.conf
  fi
  if ( ! netstat -tulpn | grep 6819); then
    echo "Waiting for slurmdbd online"
    while ( ! netstat -tulpn | grep 6819);do
      sleep 1s
    echo "."
    done
  fi
  sacctmgr -i add cluster ${CLUSTER_NAME}
  echo "start cluster"
  /usr/sbin/slurmctld
  cp -f /etc/slurm/slurm.conf /.secret/
}

### main ###
_sshd_host
_ssh_worker
_munge_start
_copy_secrets
_wait_for_worker
_slurmdbd
_slurmctld

tail -f /dev/null
