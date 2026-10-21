#!/bin/sh
# Executado (+x) pelo entrypoint da imagem base antes do comando do container:
# com DJANGO_MIGRATE=true, espera o PostGIS e aplica as migrations. Desligado por padrão, para que
# comandos avulsos (docker run ... ogrinfo, manage.py shell) não dependam do banco.
set -e

[ "${DJANGO_MIGRATE:-false}" = "true" ] || exit 0

cd /app

# logs no stderr: o stdout é a saída do comando do container
tries=30
until python manage.py shell -c "from django.db import connection; connection.ensure_connection()" > /dev/null 2>&1; do
    tries=$((tries - 1))
    if [ "$tries" -le 0 ]; then
        echo "20-django-migrate: banco indisponível" >&2
        exit 1
    fi
    sleep 2
done

python manage.py migrate --noinput >&2
