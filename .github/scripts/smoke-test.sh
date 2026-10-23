#!/bin/sh
# Smoke test de uma imagem (release, devel ou nopy): versões, drivers, bindings Python e UID arbitrário.
# Uso: .github/scripts/smoke-test.sh <imagem> [nopy]   (ex.: docker.io/ndscprm/gdal:3.12.4-py3.12)
# Com "nopy" (imagem sem Python), as verificações do venv viram verificações de que o Python não existe.
set -eu

IMAGE=${1:?uso: $0 <imagem> [nopy]}
VARIANT=${2:-}
case "$VARIANT" in "" | nopy) ;; *) echo "variante inválida: $VARIANT (use nopy ou nada)" >&2; exit 1 ;; esac

run() {
    docker run --rm -e ENTRYPOINT_QUIET_LOGS=1 "$IMAGE" "$@"
}

# drivers habilitados explicitamente no Dockerfile (GDAL/OGR_BUILD_OPTIONAL_DRIVERS=OFF)
RASTER_DRIVERS="GTiff COG VRT PNG JPEG GPKG PostGISRaster WMS WCS OGCAPI"
VECTOR_DRIVERS="OCI PostgreSQL PGDUMP SQLite GPKG OpenFileGDB Parquet Arrow KML LIBKML GML MVT GeoJSON WFS OAPIF Elasticsearch"

echo "## versões"
run gdalinfo --version
if [ "$VARIANT" != nopy ]; then
    run python -c "import numpy; from osgeo import gdal, gdal_array; print('osgeo', gdal.__version__, '| numpy', numpy.__version__)"
fi
# certificados das CAs (cURL: HTTPS, serviços OGC, /vsicurl/); na imagem python vêm da base, na nopy são instalados
run test -s /etc/ssl/certs/ca-certificates.crt

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

if [ "$VARIANT" = nopy ]; then
    echo "## sem Python (nem venv, nem /usr/local/bin/python3)"
    run sh -c '
        ! command -v python3 && ! command -v python && test ! -e /opt/geosgb/venv && test ! -e /usr/local/bin/python3' \
        || { echo "Python encontrado na imagem nopy" >&2; exit 1; }
    echo "## sem Python ok"
else
echo "## venv: versões fixadas em requirements/venv.txt"
# shellcheck disable=SC2046
run python -c '
import sys, importlib.metadata as m
bad = [p for p in sys.argv[1:] if m.version(p.split("==")[0]) != p.split("==")[1]]
assert not bad, bad
print(" ".join(sys.argv[1:]))' $(sed -n 's/^\([A-Za-z0-9_.-]*\)==\([^ ]*\).*/\1==\2/p' "$(dirname "$0")/../../requirements/venv.txt")

echo "## pip: só o do venv (o pip do sistema da imagem python é removido)"
run sh -c '
    set -e
    ! /usr/local/bin/python3 -m pip --version > /dev/null 2>&1
    test "$(command -v pip)" = /opt/geosgb/venv/bin/pip
    pip --version > /dev/null
    # ensurepip continua disponível para imagens derivadas criarem venvs
    /usr/local/bin/python3 -m venv /tmp/v && /tmp/v/bin/pip --version > /dev/null'
echo "## pip ok"
fi

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
# em sh, sem Python (vale para a nopy); sbom/cyclonedx.py grava "name" e logo abaixo "version"
run sh -c '
    set -e
    cat /opt/geosgb/share/sbom/*.cdx.json > /tmp/sbom.json
    for n in gdal arrow thrift xsimd simdjson oracle-instantclient; do
        grep -q "\"name\": \"$n\"" /tmp/sbom.json || { echo "SBOM sem $n" >&2; exit 1; }
    done
    v=$(gdalinfo --version | sed -n "s/^GDAL \([^ ,]*\).*/\1/p")
    grep -A1 "\"name\": \"gdal\"" /tmp/sbom.json | grep -q "\"version\": \"$v\"" \
        || { echo "versão do GDAL no SBOM diferente de $v" >&2; exit 1; }
    grep -A1 "\"name\":" /tmp/sbom.json | sed -n "s/.*\"\(name\|version\)\": \"\([^\"]*\)\".*/\2/p" | paste -sd " " -'
echo "## SBOM ok"

echo "## UID arbitrário (nss_wrapper)"
docker run --rm --user 12345:0 -e ENTRYPOINT_QUIET_LOGS=1 "$IMAGE" \
    sh -c 'test "$(whoami)" = sgb && test "$HOME" = /tmp && test -w "$HOME"'
# passwd/group virtuais num diretório exclusivo (mktemp, 0700), nunca num caminho fixo do /tmp
docker run --rm --user 12345:0 -e ENTRYPOINT_QUIET_LOGS=1 "$IMAGE" sh -c '
    case "$NSS_WRAPPER_PASSWD" in /tmp/nss_wrapper.*/passwd) ;; *) exit 1 ;; esac
    test "$(stat -c %a "${NSS_WRAPPER_PASSWD%/passwd}")" = 700'
# USER_NAME personalizado; nome inválido (":" injetaria campos no passwd) impede o start
docker run --rm --user 12345:0 -e ENTRYPOINT_QUIET_LOGS=1 -e USER_NAME=app.user "$IMAGE" \
    sh -c 'test "$(whoami)" = app.user'
if docker run --rm --user 12345:0 -e USER_NAME='x:x:0:0::/:/bin/sh' "$IMAGE" true 2>/dev/null; then
    echo "USER_NAME inválido foi aceito" >&2
    exit 1
fi
# stdout do comando não pode ter saída do entrypoint
out=$(docker run --rm --user 12345:0 "$IMAGE" sh -c 'echo ok' 2>/dev/null)
test "$out" = ok
echo "## nss_wrapper ok"

echo "smoke test ok: $IMAGE"
