#!/bin/bash
# Unnatended graphite/nginx/uwsgi/supervisor install for ubuntu
# it worked on Ubuntu 12.04.2 LTS on 22/03/2012
set -o nounset

ok() { echo -ne "\e[32m# $1\e[m"; }
CORES=$(nproc)

ok "Updating system\n"
aptitude update
ok "Getting packages\n"
aptitude install --assume-yes git python-setuptools python-dev python-django python-django-tagging supervisor memcached nginx libxml2-dev uwsgi-plugin-python python-twisted python-cairo python-txamqp python-memcache python-zope.interface python-tz python-pyparsing

ok "Getting graphite, carbon and whisper from git\n"
mkdir sandbox
cd sandbox/
git clone git://github.com/graphite-project/graphite-web.git
cd graphite-web
git checkout 0.9.x
cd ..
git clone git://github.com/graphite-project/carbon.git
cd carbon
git checkout 0.9.x
cd ..
git clone git://github.com/graphite-project/whisper.git
cd whisper
git checkout 0.9.x
cd ..

ok "Installing whisper\n"
cd whisper
python setup.py install

ok "Installing carbon\n"
cd ../carbon
python setup.py install

ok "Installing graphite-web\n"
cd ../graphite-web
python setup.py install

ok "Setting the Database\n"
cd /opt/graphite/webapp/graphite
yes no | python manage.py syncdb

ok "Supervisor config\n"
cat > /etc/supervisor/supervisord.conf <<-EOF
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisord]
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
childlogdir=/var/log/supervisor

[supervisorctl]
serverurl=unix:///var/run//supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[program:nginx]
command=/usr/sbin/nginx
autostart=true
autorestart=true
stopsignal=QUIT

[program:uwsgi-graphite]
command=uwsgi_python -b 65536 --socket 127.0.0.1:3031 --master --processes $CORES --limit-as 512 --chdir=/opt/graphite/webapp --env DJANGO_SETTINGS_MODULE=graphite.settings --module='django.core.handlers.wsgi:WSGIHandler()'
autostart=true
autorestart=true
stopsignal=QUIT

[program:memcached]
command=/usr/bin/memcached -m 64 logfile /var/log/memcached.log
autostart=true
autorestart=true
user=nobody

[program:carbon-cache]
command=python /opt/graphite/bin/carbon-cache.py --debug start
autostart=true
autorestart=true
stopsignal=QUIT

[program:carbon-relay]
command=python /opt/graphite/bin/carbon-relay.py --debug start
autostart=true
autorestart=true
stopsignal=QUIT
EOF

ok "Nginx config\n"
cat > /etc/nginx/nginx.conf <<-EOF
daemon           off;
user             www-data;
worker_processes $CORES;
error_log        /var/log/nginx/error.log;
pid              /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    log_format main   '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for" \$request_time \$upstream_response_time';
    add_header        P3P "CP=\\"CAO PSA OUR\\"";
    large_client_header_buffers  4  64k;
    include           /etc/nginx/mime.types;
    access_log        /var/log/nginx/access.log main;
    sendfile          on;
    keepalive_timeout 65;
    tcp_nodelay       on;
    gzip              on;
    gzip_disable      "MSIE [1-6]\.(?!.*SV1)";
    include           /etc/nginx/conf.d/*.conf;
    include           /etc/nginx/sites-enabled/graphite;
}
EOF

ok "Nginx graphite site\n"
cat > /etc/nginx/sites-enabled/graphite <<-EOF
server {
    listen       80 default;
    server_name  $(hostname);
    access_log  /var/log/nginx/graphite.access.log main;
    location / {
        include uwsgi_params;
        uwsgi_pass  127.0.0.1:3031;
    }
}
EOF

ok "Creating local_settings.py\n"
cat > /opt/graphite/conf/local_settings.py <<-EOF
TIME_ZONE = 'Europe/Madrid'
DEBUG     = True
EOF

ok "Linking local_setting.py to webapp/graphite\n"
ln -s /opt/graphite/conf/local_settings.py /opt/graphite/webapp/graphite/local_settings.py

ok "Copying config files\n"
cp -v /opt/graphite/conf/storage-schemas.conf.example /opt/graphite/conf/storage-schemas.conf
cp -v /opt/graphite/conf/relay-rules.conf.example /opt/graphite/conf/relay-rules.conf
cp -v /opt/graphite/conf/graphite.wsgi.example /opt/graphite/conf/graphite.wsgi
cp -v /opt/graphite/conf/carbon.conf.example /opt/graphite/conf/carbon.conf

ok "Removing nginx startup\n"
update-rc.d -f nginx remove

ok "Adding supervisor to startup\n"
update-rc.d -f supervisor defaults

ok "Chown dir and start supervisor\n"
chown -R www-data:www-data /opt/graphite
supervisorctl reread
supervisorctl reload
sleep 2

ok "Supervisor status\n"
supervisorctl status
