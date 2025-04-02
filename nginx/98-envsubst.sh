envsubst '${DOMAIN}' < /etc/nginx/conf.d/funnel.conf.template > /etc/nginx/conf.d/funnel.conf
nginx -g 'daemon off;'
