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

echo "## Parquet: codecs e Thrift embutido"
run sh -c '
    set -e; cd /tmp
    echo "{\"type\":\"Feature\",\"properties\":{\"n\":1},\"geometry\":{\"type\":\"Point\",\"coordinates\":[-45,-5]}}" > p.geojson
    for c in SNAPPY GZIP BROTLI ZSTD LZ4_RAW; do
        ogr2ogr -f Parquet -lco COMPRESSION=$c "v_$c.parquet" p.geojson
        ogrinfo -ro -so -al "v_$c.parquet" | grep -q "Feature Count: 1"
    done
    # Arrow/Parquet compilados na imagem com Thrift estático: nenhum libthrift do Debian
    ! dpkg-query -W -f "\${Status}\n" "libthrift*" 2> /dev/null | grep -q "ok installed"'
echo "## Parquet ok"

echo "## proteções de compilação (HARDENING_CFLAGS/LDFLAGS)"
# só no devel, que tem readelf; os binários do release são os mesmos, sem os símbolos de debug
run sh -c '
    command -v readelf > /dev/null || { echo "readelf ausente, pulando"; exit 0; }
    for f in /opt/geosgb/lib/libgdal.so /opt/geosgb/lib/libarrow.so /opt/geosgb/lib/libparquet.so /opt/geosgb/bin/gdalinfo \
             /opt/geosgb/venv/lib/python*/site-packages/osgeo/_gdal.*.so; do
        readelf -dW "$f" | grep -q BIND_NOW || { echo "sem RELRO completo: $f" >&2; exit 1; }
        readelf -sW --dyn-syms "$f" | grep -q __stack_chk_fail || { echo "sem stack protector: $f" >&2; exit 1; }
        readelf -sW --dyn-syms "$f" | grep -q "_chk@" || { echo "sem _FORTIFY_SOURCE: $f" >&2; exit 1; }
    done
    echo "ok"'

echo "## SBOM dos componentes fora do apt (/opt/geosgb/share/sbom)"
run python -c '
import glob, json
from osgeo import gdal
comps = {c["name"]: c["version"] for f in glob.glob("/opt/geosgb/share/sbom/*.cdx.json") for c in json.load(open(f))["components"]}
missing = {"gdal", "arrow", "thrift", "xsimd", "simdjson", "oracle-instantclient"} - comps.keys()
assert not missing, missing
assert comps["gdal"] == gdal.__version__, comps["gdal"]
print(", ".join(f"{n} {v}" for n, v in sorted(comps.items())))'
echo "## SBOM ok"

echo "## UID arbitrário (nss_wrapper)"
docker run --rm --user 12345:0 -e ENTRYPOINT_QUIET_LOGS=1 "$IMAGE" \
    sh -c 'test "$(whoami)" = sgb && test "$HOME" = /tmp && test -w "$HOME"'
# stdout do comando não pode ter saída do entrypoint
out=$(docker run --rm --user 12345:0 "$IMAGE" sh -c 'echo ok' 2>/dev/null)
test "$out" = ok
echo "## nss_wrapper ok"

echo "smoke test ok: $IMAGE"
