#!/bin/sh

# Import variables from .env
set -a
. .env
set +a

if [ -z $vols ]; then
    printf "\$vols is not declared in the environment."
fi

# Create folders and copy files
mkdir -p $vols/certbot/www
mkdir -p $vols/certbot/conf
mkdir -p $vols/nginx/entrypoints
mkdir -p $vols/nginx/conf
cp nginx/funnel.conf $vols/nginx/conf/
cp nginx/99-autoreload.sh $vols/nginx/entrypoints/

# Certbot setup
rsa_key_size=4096
data_path="$vols/certbot/"
email="$CERTBOT_EMAIL"
staging=0

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
    echo "### Downloading recommended TLS parameters ..."
    mkdir -p "$data_path/conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf >"$data_path/conf/options-ssl-nginx.conf"
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem >"$data_path/conf/ssl-dhparams.pem"
    echo
fi

# Dummy certs
echo "Generating dummies"
path="/etc/letsencrypt/live/$DOMAIN"
mkdir -p "$data_path/conf/live/$DOMAIN"
docker compose -f ./docker-compose.yml run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

# Start nginx with the dummies
echo "Start dummy cert nginx"
docker compose -f ./docker-compose.yml up --force-recreate -d nginx
echo

# Delete dummy certs
echo "Deleting dummy certs"
docker compose  -f "docker-compose.yml" run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$DOMAIN && \
  rm -Rf /etc/letsencrypt/archive/$DOMAIN && \
  rm -Rf /etc/letsencrypt/renewal/$DOMAIN.conf" certbot
echo

# Any domain arguments if required
domain_args=""
for domain in "${domains[@]}"; do
    domain_args="$domain_args -d $domain"
done

# Validate email address being available
case "$email" in
"") email_arg="--register-unsafely-without-email" ;;
*) email_arg="--email $email" ;;
esac

# Set staging arg
if [ $staging != "0" ]; then staging_arg="--staging"; fi

# Get letsencrypt certs
echo "Obtaining letsencrypt certificates"
docker compose -f ./docker-compose.yml run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

# Reload nginx to use new certs
echo "Reloading nginx"
docker compose -f "docker-compose.yml" exec nginx nginx -s reload