#!/bin/sh
set -e -x

# Temporary work dir
tmpdir="`mktemp -d`"
cd "$tmpdir"

# Install prerequisites
export DEBIAN_FRONTEND=noninteractive
apt-get update -q --yes
apt-get install -q --yes logrotate vim-nox hardlink wget ca-certificates apt-transport-https

# Download and install Chef's packages
wget -nv https://web-dl.packagecloud.io/chef/stable/packages/ubuntu/trusty/chef-server-core_12.3.1-1_amd64.deb
wget -nv https://web-dl.packagecloud.io/chef/stable/packages/ubuntu/trusty/chef_12.6.0-1_amd64.deb

sha1sum -c - <<EOF
b98fab36311ce8237baa60b73037c6c6d0e49c7c  chef-server-core_12.3.1-1_amd64.deb
8465cb169320e3c913a45109597e449f289549ac  chef_12.6.0-1_amd64.deb
EOF

dpkg -i chef-server-core_12.3.1-1_amd64.deb chef_12.6.0-1_amd64.deb

# Extra setup
rm -rf /etc/opscode
mkdir -p /etc/cron.hourly
ln -sfv /var/opt/opscode/log /var/log/opscode
ln -sfv /var/opt/opscode/etc /etc/opscode
ln -sfv /opt/opscode/sv/logrotate /opt/opscode/service
ln -sfv /opt/opscode/embedded/bin/sv /opt/opscode/init/logrotate
chef-apply -e 'chef_gem "knife-opc"'

# Cleanup
cd /
rm -rf $tmpdir /tmp/install.sh /var/lib/apt/lists/* /var/cache/apt/archives/*
