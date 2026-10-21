# GeoDjango sobre a imagem release do GDAL (sem compilação: Django usa o GDAL e o GEOS via ctypes)
ARG GDAL_IMAGE=docker.io/ndscprm/gdal
ARG GDAL_TAG=3.12.4-py3.12

FROM ${GDAL_IMAGE}:${GDAL_TAG}

WORKDIR /app
ENV DJANGO_SETTINGS_MODULE=geoapp.settings

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY manage.py .
COPY geoapp/ geoapp/
COPY places/ places/
COPY data/ data/

# arquivos estáticos (admin, mapa do GISModelAdmin) gerados no build: o container não precisa escrever em /app
RUN DJANGO_SECRET_KEY=build python manage.py collectstatic --noinput > /dev/null && \
    # confere que o Django carrega o GDAL e o GEOS da imagem
    DJANGO_SECRET_KEY=build python -c "import django; django.setup(); from django.contrib.gis import gdal, geos; print('GDAL', gdal.gdal_full_version().decode(), '| GEOS', geos.geos_version().decode())"

# executável (755): roda como processo próprio, antes do comando do container
COPY --chmod=755 docker-entrypoint.d/20-django-migrate.sh /docker-entrypoint.d/

EXPOSE 8000

# o ENTRYPOINT da imagem base (/docker-entrypoint.sh) é mantido; só o CMD muda
CMD ["gunicorn", "geoapp.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2"]
