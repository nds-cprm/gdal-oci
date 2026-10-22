#!/bin/sh
# Smoke test de uma imagem (release ou devel): versões, drivers, bindings Python e UID arbitrário.
# Uso: .github/scripts/smoke-test.sh <imagem>   (ex.: docker.io/ndscprm/gdal:3.12.4-py3.12)
set -eu

IMAGE=${1:?uso: $0 <imagem>}

run() {
    docker run --rm -e ENTRYPOINT_QUIET_LOGS=1 "$IMAGE" "$@"
}

# drivers habilitados explicitamente no Dockerfile (GDAL/OGR_BUILD_OPTIONAL_DRIVERS=OFF)
RASTER_DRIVERS="GTiff COG VRT PNG JPEG GPKG PostGISRaster WMS WCS OGCAPI"
VECTOR_DRIVERS="OCI PostgreSQL PGDUMP SQLite GPKG OpenFileGDB Parquet Arrow KML LIBKML GML MVT GeoJSON WFS OAPIF Elasticsearch"

echo "## versões"
run gdalinfo --version
run python -c "import numpy; from osgeo import gdal, gdal_array; print('osgeo', gdal.__version__, '| numpy', numpy.__version__)"

missing=""
raster=$(run gdalinfo --formats)
for d in $RASTER_DRIVERS; do
    echo "$raster" | grep -q -E "^ +$d -" || missing="$missing raster:$d"
done
vector=$(run ogrinfo --formats)
for d in $VECTOR_DRIVERS; do
    echo "$vector" | grep -q -E "^ +$d -" || missing="$missing vector:$d"
done
if [ -n "$missing" ]; then
    echo "drivers ausentes:$missing" >&2
    exit 1
fi
echo "## drivers ok"

echo "## escrita e leitura (COG, GPKG raster e vetor)"
run sh -c '
    set -e; cd /tmp
    gdal_create -q -of GTiff -outsize 256 256 -bands 3 -burn 1 -a_srs EPSG:4326 -a_ullr -50 0 -40 -10 r.tif
    gdal_translate -q -of COG r.tif c.tif
    gdal_translate -q -of GPKG r.tif r.gpkg
    echo "{\"type\":\"Feature\",\"properties\":{\"n\":1},\"geometry\":{\"type\":\"Point\",\"coordinates\":[-45,-5]}}" > p.geojson
    ogr2ogr -f GPKG v.gpkg p.geojson
    ogr2ogr -f LIBKML v.kmz p.geojson
    ogr2ogr -f Parquet v.parquet p.geojson
    gdalinfo c.tif | grep -q "LAYOUT=COG"
    gdalinfo r.gpkg > /dev/null
    for f in v.gpkg v.kmz v.parquet; do ogrinfo -ro -so -al "$f" | grep -q "Feature Count: 1"; done'
echo "## escrita e leitura ok"

echo "## UID arbitrário (nss_wrapper)"
docker run --rm --user 12345:0 -e ENTRYPOINT_QUIET_LOGS=1 "$IMAGE" \
    sh -c 'test "$(whoami)" = sgb && test "$HOME" = /tmp && test -w "$HOME"'
# stdout do comando não pode ter saída do entrypoint
out=$(docker run --rm --user 12345:0 "$IMAGE" sh -c 'echo ok' 2>/dev/null)
test "$out" = ok
echo "## nss_wrapper ok"

echo "smoke test ok: $IMAGE"
