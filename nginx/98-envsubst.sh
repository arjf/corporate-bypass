envsubst '${DOMAIN}' < /etc/nginx/conf/funnel.conf.template > /etc/nginx/conf/funnel.conf
nginx -g 'daemon off;'
