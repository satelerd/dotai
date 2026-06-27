#!/usr/bin/env bash
# Bring the sandbox up: a `tester` user that can ssh to itself by key, plus a
# running sshd. Everything the teleport transport needs, isolated in-container.
set -e

id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester
mkdir -p /run/sshd
ssh-keygen -A   # host keys

su - tester -c '
  set -e
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  [ -f ~/.ssh/id_tp ] || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_tp -q
  cat ~/.ssh/id_tp.pub > ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  cat > ~/.ssh/config <<EOF
Host localhost
  HostName 127.0.0.1
  User tester
  IdentityFile ~/.ssh/id_tp
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
  chmod 600 ~/.ssh/config
  git config --global init.defaultBranch main
  git config --global user.email tester@example.com
  git config --global user.name  tester
'

/usr/sbin/sshd
exec tail -f /dev/null
