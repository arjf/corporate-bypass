#!/bin/sh
set -e # Exit if any command exits non zero

# Import variables from .env
if [ ! -f ./.env ]; then
    echo "Error: .env file is missing"
    exit 1
fi

set -a
. ./.env
set +a

# Variable checks
if [ -z "$vols" ]; then
    echo "Error: \$vols is not declared in the environment."
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo "Error: \$DOMAIN is not declared in the environment."
    exit 1
fi

if [ -z "$CERTBOT_EMAIL" ]; then
    echo "Warning: \$CERTBOT_EMAIL is not set. Proceeding without email."
fi

# Command checks
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is missing"
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "Error: Docker Compose is missing"
    exit 1
fi

# Check if required files exist
if [ ! -f nginx/funnel.conf.template ]; then
    echo "Error: nginx/funnel.conf.template missing"
    exit 1
fi

if [ ! -f nginx/99-autoreload.sh ]; then
    echo "Error: nginx/99-autoreload.sh missing"
    exit 1
fi

if [ ! -f nginx/98-envsubst.sh ]; then
    echo "Error: nginx/98-envsubst.sh missing"
    exit 1
fi

# Create folders and copy files
echo "Creating folders"
mkdir -p "$vols/certbot/www"
mkdir -p "$vols/certbot/conf"
mkdir -p "$vols/nginx/entrypoints"
mkdir -p "$vols/nginx/conf"
cp nginx/funnel.conf.template "$vols/nginx/conf/"
cp nginx/99-autoreload.sh "$vols/nginx/entrypoints/"
cp nginx/99-envsubst.sh "$vols/nginx/entrypoints/"
chmod +x "$vols/nginx/entrypoints/99-autoreload.sh"
chmod +x "$vols/nginx/entrypoints/99-envsubst.sh"

# If single domain set array to single doamin
if [ -z "$domains" ]; then
    domains="$DOMAIN"
fi

# Certbot setup
echo "Setting up certbot"
rsa_key_size=4096
data_path="$vols/certbot/"
email="$CERTBOT_EMAIL"
staging=0

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
    echo "Downloading recommended TLS parameters"
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
for domain in $domains; do
    domain_args="$domain_args -d $domain"
done

# Validate email address being available
case "$email" in
"") email_arg="--register-unsafely-without-email" ;;
*) email_arg="--email $email" ;;
esac

# Set staging arg
if [ "$staging" != "0" ]; then staging_arg="--staging"; fi

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