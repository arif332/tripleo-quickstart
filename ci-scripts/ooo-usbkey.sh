#!/bin/bash
# CI test that tests the USB key method of using tripleo-quickstart
# Usage: basic.sh <release> <build_system> <config> <job_type>
set -eux

# CONFIG and JOB_TYPE are not used here, but kept for
# consistency with other jobs to make JJB cleaner.
RELEASE=$1
BUILD_SYS=$2
CONFIG=$3
JOB_TYPE=$4

URL=http://artifacts.ci.centos.org/artifacts/rdo/images
UNDERCLOUD=$URL/$RELEASE/$BUILD_SYS/stable/undercloud.qcow2
sshcmd='ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
scpcmd='scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

# Create a non-root user with passwordless sudo permissions on the virthost
# This is a requirement of the usbkey script, but the CI nodes do not have it
$sshcmd root@$VIRTHOST <<-EOF
  useradd stack
  mkdir /home/stack/.ssh
  cp /root/.ssh/authorized_keys /home/stack/.ssh/
  chown -R stack:stack /home/stack
  echo "Defaults:stack !requiretty" > /etc/sudoers.d/stack
  echo "stack ALL=(root) NOPASSWD:ALL" >> /etc/sudoers.d/stack
  chmod 0440 /etc/sudoers.d/stack
EOF

# Copy artifacts to the CI provided virthost to simulate USB key
$sshcmd stack@$VIRTHOST <<-EOF
  if [[ ! -f /tmp/usb/undercloud.qcow2 ]]; then
    mkdir -p /tmp/usb
    curl -o /tmp/usb/undercloud.qcow2 $UNDERCLOUD
    curl -o /tmp/usb/undercloud.qcow2.md5 $UNDERCLOUD.md5
  else
    echo "undercloud.qcow2 file was found, skipping download"
  fi
EOF

#Ensure rsync is installed on target, required w/ ssh as the protocol
$sshcmd root@$VIRTHOST <<-EOF
  yum -y install rsync
EOF

#$scpcmd -r $WORKSPACE/tripleo-quickstart stack@$VIRTHOST:/tmp/usb/
rsync -avz -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" --progress $WORKSPACE/tripleo-quickstart stack@$VIRTHOST:/tmp/usb/
$sshcmd stack@$VIRTHOST "cp /tmp/usb/tripleo-quickstart/ci-scripts/usbkey/* /tmp/usb/"
$sshcmd stack@$VIRTHOST "cp /tmp/usb/tripleo-quickstart/ci-scripts/usbkey/quickstart-usb.yml /tmp/usb/tripleo-quickstart/playbooks/"
# Simulate executable bit being unset when mounting usbkey
$sshcmd stack@$VIRTHOST "chmod -x /tmp/usb/RUN_ME.sh /tmp/usb/tripleo-quickstart/quickstart.sh"

# Run the USB script
$sshcmd stack@$VIRTHOST 'pushd /tmp/usb; bash RUN_ME.sh'

# Support collect logs on the virthost by providing hosts and ssh config
export ANSIBLE_INVENTORY=$WORKSPACE/hosts
export SSH_CONFIG=$WORKSPACE/ssh.config.ansible
export ANSIBLE_SSH_ARGS="-F ${SSH_CONFIG}"
$scpcmd stack@$VIRTHOST:~/.quickstart/ssh.config* $WORKSPACE/
$scpcmd stack@$VIRTHOST:~/.quickstart/hosts* $WORKSPACE/
$scpcmd stack@$VIRTHOST:~/.quickstart/id_* $WORKSPACE/
sed -i 's,\/home\/stack\/\.quickstart,'"$WORKSPACE"',g' $WORKSPACE/ssh.config.ansible
bash ci-scripts/collect-logs.sh


