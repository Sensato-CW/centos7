#!/bin/bash

echo "Backing up repository settings."
sudo cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak

echo "Updating the repository."
# Update the [base] repository
sudo sed -i 's|^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infra|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infra|' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|^#baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/|baseurl=http://vault.centos.org/centos/$releasever/os/$basearch/|' /etc/yum.repos.d/CentOS-Base.repo

# Update the [updates] repository
sudo sed -i 's|^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates&infra=$infra|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates&infra=$infra|' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|^#baseurl=http://mirror.centos.org/centos/$releasever/updates/$basearch/|baseurl=http://vault.centos.org/centos/$releasever/updates/$basearch/|' /etc/yum.repos.d/CentOS-Base.repo

# Update the [extras] repository
sudo sed -i 's|^mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras&infra=$infra|#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras&infra=$infra|' /etc/yum.repos.d/CentOS-Base.repo
sudo sed -i 's|^#baseurl=http://mirror.centos.org/centos/$releasever/extras/$basearch/|baseurl=http://vault.centos.org/centos/$releasever/extras/$basearch/|' /etc/yum.repos.d/CentOS-Base.repo

# Disable the CentOS Plus repo (optional, only if you don't need it)
sudo sed -i 's|^enabled=1|enabled=0|' /etc/yum.repos.d/CentOS-Base.repo

echo "Performing yum update."
sudo yum clean all
sudo yum update -y
sudo yum makecache

echo "Installing dependencies for CloudWave HIDS."
sudo yum --enablerepo=base,updates,extras install -y perl gcc make zlib-devel pcre2-devel libevent-devel curl wget git expect

echo "Retrieving Installer."

# Using expect to handle the interactive prompt
expect -c "
spawn wget -q -O - https://updates.atomicorp.com/installers/atomic | sudo bash
expect \"Do you agree to these terms?\" { send \"yes\r\" }
expect eof
"

echo "Installing HIDS agent."
sudo yum install ossec-hids-agent
