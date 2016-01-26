#!/bin/sh
set -e -x

# Temporary work dir
tmpdir="`mktemp -d`"
cd "$tmpdir"

# Install prerequisites
export DEBIAN_FRONTEND=noninteractive


wget -nv https://web-dl.packagecloud.io/chef/stable/packages/ubuntu/trusty/chef-manage_2.1.1-1_amd64.deb
sha1sum -c - <<EOF
	b6c87fd29d8af63413eba1b437dcae58712ff661  chef-manage_2.1.1-1_amd64.deb
EOF

dpkg -i chef-manage_2.1.1-1_amd64.deb


# Cleanup
cd /
rm -rf $tmpdir /tmp/install.sh /var/lib/apt/lists/* /var/cache/apt/archives/*
