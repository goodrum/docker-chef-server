# -*- conf -*-

FROM goodrum/docker-chef-server:12.3.1
MAINTAINER Jeremy Goodrum <jeremy.b.goodrum@gmail.com>

EXPOSE 80 443
VOLUME /var/opt/opscode
VOLUME /var/opt/chef-manage

COPY install.sh /tmp/install.sh

RUN [ "/bin/sh", "/tmp/install.sh" ]

COPY init.rb /init.rb
COPY chef-server.rb /.chef/chef-server.rb
COPY logrotate /opt/opscode/sv/logrotate
COPY knife.rb /etc/chef/knife.rb
COPY backup.sh /usr/local/bin/chef-server-backup

ENV KNIFE_HOME /etc/chef
ENV PUBLIC_URL ""

CMD [ "/opt/opscode/embedded/bin/ruby", "/init.rb" ]
