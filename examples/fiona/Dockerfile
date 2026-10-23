# fiona compilado contra o GDAL da imagem, estendendo o venv do devel
# GDAL_TAG é usado nos dois estágios, então devel e release-py são sempre da mesma versão
ARG GDAL_IMAGE=docker.io/ndscprm/gdal
ARG GDAL_TAG=3.12.4-py3.12

# 1) Estende o venv no devel, que tem compilador e headers do GDAL
FROM ${GDAL_IMAGE}:${GDAL_TAG}-devel AS build

ARG FIONA_VERSION=1.10.1

COPY requirements.txt /tmp/requirements.txt
# --no-binary: compila o fiona contra o GDAL da imagem em vez de usar a wheel do PyPI (que traz outro GDAL)
RUN pip install --no-cache-dir --no-binary fiona "fiona==${FIONA_VERSION}" && \
    pip install --no-cache-dir -r /tmp/requirements.txt && \
    # garante que o fiona ficou ligado ao GDAL da imagem (falha o build se não ficou)
    python -c "import fiona; from osgeo import gdal; assert fiona.__gdal_version__ == gdal.__version__, fiona.__gdal_version__"

# 2) Imagem final: release-py + venv estendido
FROM ${GDAL_IMAGE}:${GDAL_TAG}

# substitui o venv inteiro: todo pip install que compila precisa estar no estágio build
COPY --from=build /opt/geosgb/venv /opt/geosgb/venv

WORKDIR /app
COPY app.py .
CMD ["python", "app.py"]
