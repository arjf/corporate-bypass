envsubst '${DOMAIN}' < /etc/nginx/conf/nginx.conf.template > /etc/nginx/conf/funnel.conf
nginx -g 'daemon off;'
