ARG PYTHON_VERSION=3.12
ARG DEBIAN_VERSION=trixie

ARG BASE_DIR=/opt/geosgb


FROM python:${PYTHON_VERSION}-${DEBIAN_VERSION} AS devel

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG BASE_DIR

# Install dependencies; upgrade first applies the Debian fixes released after the python base image was built
# (the layer is cached in CI, so devel only gets them again when the base image or this line changes)
RUN apt-get -y update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        build-essential \
        cmake \
        gdb \
        ca-certificates \
        unzip \
        wget && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/*

# Oracle
# SHA256 from Oracle download pages (linux-x86-64 / linux-arm-aarch64)
# the download directory is the version without dots (19.32.0.0.0 -> 1932000)
ARG ORACLE_INSTANTCLIENT_VERSION=19.32.0.0.0
ARG ORACLE_BASICLITE_SHA256_X64=16947fc0fa55b861903aad6f9d2ddee7b4fedaf789a175ee36b46b82ec64fcbd
ARG ORACLE_SDK_SHA256_X64=1698b3be6dde8b7e90501a62122cb9c160c712eb709deb7129d915a504b76158

ARG ORACLE_BASICLITE_SHA256_ARM64=2c7c657b1e77b95a969e70f9af816b5e88f40047249c820936aa87a126d8e4f4
ARG ORACLE_SDK_SHA256_ARM64=be3b37817943102cb051fad80f5dc821821cf1616ffd0983c2ded81621c760d3

WORKDIR /tmp

RUN --mount=type=bind,source=sbom/cyclonedx.py,target=/tmp/cyclonedx.py \
    apt-get -y update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        libaio1t64 && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/* && \
    # install oracle client
    ARCH=$(dpkg --print-architecture | sed 's/amd/x/g') && \
    case "$ARCH" in \
        x64) BASICLITE_SHA256=${ORACLE_BASICLITE_SHA256_X64}; SDK_SHA256=${ORACLE_SDK_SHA256_X64} ;; \
        arm64) BASICLITE_SHA256=${ORACLE_BASICLITE_SHA256_ARM64}; SDK_SHA256=${ORACLE_SDK_SHA256_ARM64} ;; \
        *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac && \
    ORACLE_URL="https://download.oracle.com/otn_software/linux/instantclient/${ORACLE_INSTANTCLIENT_VERSION//./}" && \
    wget -qO oracle.zip "${ORACLE_URL}/instantclient-basiclite-linux.$ARCH-${ORACLE_INSTANTCLIENT_VERSION}dbru.zip" && \
    wget -qO oracle-sdk.zip "${ORACLE_URL}/instantclient-sdk-linux.$ARCH-${ORACLE_INSTANTCLIENT_VERSION}dbru.zip" && \
    # check integrity
    echo "${BASICLITE_SHA256}  oracle.zip" | sha256sum -c - && \
    echo "${SDK_SHA256}  oracle-sdk.zip" | sha256sum -c - && \
    # Extract downloaded binaries
    ORACLE_INSTANTCLIENT_DIR=${BASE_DIR}/oracle && \
    mkdir -p "${ORACLE_INSTANTCLIENT_DIR}" && \
    unzip -d "${ORACLE_INSTANTCLIENT_DIR}" oracle.zip && \
    unzip -od "${ORACLE_INSTANTCLIENT_DIR}" oracle-sdk.zip && \
    rm oracle.zip oracle-sdk.zip && \
    # Oracle client looks for libaio.so.1 (Debian trixie ships libaio.so.1t64); the release stage recreates it
    ARCH=$(uname -m) && \
    ln -s "$(find "/usr/lib/$ARCH-linux-gnu" -name 'libaio.so.1*' -type f -print -quit)" "/usr/lib/$ARCH-linux-gnu/libaio.so.1" && \
    CLIENT_DIR=$(find "${ORACLE_INSTANTCLIENT_DIR}" -name 'instantclient*' -type d -print -quit) && \
    echo "$CLIENT_DIR" > /etc/ld.so.conf.d/oracle.conf && \
    ldconfig && \
    # SBOM: components outside apt are invisible to the image scanners (see sbom/cyclonedx.py)
    mkdir -p "${BASE_DIR}/share/sbom" && \
    python3 /tmp/cyclonedx.py "${BASE_DIR}/share/sbom/oracle-instantclient.cdx.json" \
        "oracle-instantclient|${ORACLE_INSTANTCLIENT_VERSION}|pkg:generic/oracle/instantclient@${ORACLE_INSTANTCLIENT_VERSION}||Oracle Free Use Terms and Conditions"

# Install GDAL dependencies, with Oracle support (Arrow/Parquet are built from source in the next step)
RUN apt-get -y update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        swig \
        # Arrow/Parquet build: Boost headers (Thrift), compression codecs, re2/utf8proc (compute)
        libboost-dev \
        libbrotli-dev \
        libbz2-dev \
        liblz4-dev \
        libre2-dev \
        libsnappy-dev \
        libutf8proc-dev \
        libzstd-dev \
        zlib1g-dev \
        libcurl4-openssl-dev \
        libexpat1-dev \
        libsfcgal-dev \
        libgeos-dev \
        libgeotiff-dev \
        libjson-c-dev \
        libkml-dev \
        # libmariadb-dev \
        libmuparser-dev \
        libpq-dev \
        libproj-dev \
        # libprotobuf-dev \
        # librasterlite2-dev \
        # libspatialite-dev \
        libsqlite3-dev \
        # internal
        # libpng-dev \
        libqhull-dev \
        libxerces-c-dev \
        libxml2-dev && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/*

# Apache Thrift + Apache Arrow/Parquet, built from source: Parquet uses Thrift to read the file metadata
# and Debian's Thrift (0.19 in trixie) has open CVEs, so Thrift is built at a fixed release and linked
# statically into libparquet. SHA256 taken from tarballs whose .asc was verified against
# https://downloads.apache.org/{thrift,arrow}/KEYS
# Hardening flags for everything compiled here (Thrift, Arrow, GDAL): Debian's gcc, unlike Ubuntu's,
# does not enable them by default and these libraries parse untrusted files and network responses
ARG HARDENING_CFLAGS="-fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=3"
ARG HARDENING_LDFLAGS="-Wl,-z,relro,-z,now"

ARG THRIFT_VERSION=0.25.0
ARG THRIFT_SHA256=66da4707214c54c94bac082103dc67adaf9e08925662700f269170a7b534b214
ARG ARROW_VERSION=26.0.0
ARG ARROW_SHA256=b153ef472dd89ef4cb84867ca238f2a3a9347d8f4a78913d16ca2201606f0425

# the CDN only serves current releases; older ones are moved to archive.apache.org
RUN --mount=type=bind,source=sbom/cyclonedx.py,target=/tmp/cyclonedx.py \
    apache_download() { wget -qO "$2" "https://dlcdn.apache.org/$1" || wget -qO "$2" "https://archive.apache.org/dist/$1"; } && \
    apache_download "thrift/${THRIFT_VERSION}/thrift-${THRIFT_VERSION}.tar.gz" thrift.tar.gz && \
    apache_download "arrow/arrow-${ARROW_VERSION}/apache-arrow-${ARROW_VERSION}.tar.gz" arrow.tar.gz && \
    echo "${THRIFT_SHA256}  thrift.tar.gz" | sha256sum -c - && \
    echo "${ARROW_SHA256}  arrow.tar.gz" | sha256sum -c - && \
    mkdir thrift arrow && \
    tar -zxf thrift.tar.gz -C thrift --strip-components=1 && \
    tar -zxf arrow.tar.gz -C arrow --strip-components=1 && \
    rm thrift.tar.gz arrow.tar.gz && \
    # Thrift: C++ library only, static and PIC (linked into libparquet.so); no compiler, TLS, zlib or libevent
    cmake -S thrift -B thrift/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="${HARDENING_CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${HARDENING_CFLAGS}" \
        -DCMAKE_INSTALL_PREFIX=${BASE_DIR} \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_COMPILER=OFF \
        -DBUILD_TESTING=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TUTORIALS=OFF \
        -DWITH_CPP=ON \
        -DWITH_C_GLIB=OFF \
        -DWITH_JAVA=OFF \
        -DWITH_JAVASCRIPT=OFF \
        -DWITH_NODEJS=OFF \
        -DWITH_PYTHON=OFF \
        -DWITH_QT5=OFF \
        -DWITH_LIBEVENT=OFF \
        -DWITH_OPENSSL=OFF \
        -DWITH_ZLIB=OFF && \
    cmake --build thrift/build --parallel "$(nproc)" --target install && \
    # Arrow: the modules used by the GDAL Arrow/Parquet drivers, codecs and re2/utf8proc from Debian;
    # xsimd and simdjson are newer than Debian's, so Arrow fetches them (SHA256 from its versions.txt)
    cmake -S arrow/cpp -B arrow/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="${HARDENING_CFLAGS}" \
        -DCMAKE_CXX_FLAGS="${HARDENING_CFLAGS}" \
        -DCMAKE_SHARED_LINKER_FLAGS="${HARDENING_LDFLAGS}" \
        -DCMAKE_EXE_LINKER_FLAGS="${HARDENING_LDFLAGS}" \
        -DCMAKE_INSTALL_PREFIX=${BASE_DIR} \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DARROW_BUILD_STATIC=OFF \
        -DARROW_DEPENDENCY_SOURCE=SYSTEM \
        -Dxsimd_SOURCE=BUNDLED \
        -Dsimdjson_SOURCE=BUNDLED \
        -DThrift_ROOT=${BASE_DIR} \
        -DARROW_THRIFT_USE_SHARED=OFF \
        -DARROW_COMPUTE=ON \
        -DARROW_ACERO=ON \
        -DARROW_DATASET=ON \
        -DARROW_FILESYSTEM=ON \
        -DARROW_IPC=ON \
        -DARROW_PARQUET=ON \
        -DARROW_WITH_BROTLI=ON \
        -DARROW_WITH_BZ2=ON \
        -DARROW_WITH_LZ4=ON \
        -DARROW_WITH_SNAPPY=ON \
        -DARROW_WITH_ZLIB=ON \
        -DARROW_WITH_ZSTD=ON \
        -DARROW_WITH_RE2=ON \
        -DARROW_WITH_UTF8PROC=ON \
        -DARROW_JEMALLOC=OFF \
        -DARROW_MIMALLOC=OFF && \
    cmake --build arrow/build --parallel "$(nproc)" --target install && \
    # SBOM: Thrift is static in libparquet; xsimd (headers) and simdjson (static) are bundled by Arrow
    XSIMD_VERSION=$(sed -n 's/^ARROW_XSIMD_BUILD_VERSION=//p' arrow/cpp/thirdparty/versions.txt) && \
    SIMDJSON_VERSION=$(sed -n 's/^ARROW_SIMDJSON_BUILD_VERSION=v\{0,1\}//p' arrow/cpp/thirdparty/versions.txt) && \
    test -n "$XSIMD_VERSION" && test -n "$SIMDJSON_VERSION" && \
    python3 /tmp/cyclonedx.py "${BASE_DIR}/share/sbom/apache-arrow.cdx.json" \
        "arrow|${ARROW_VERSION}|pkg:generic/apache/arrow@${ARROW_VERSION}|cpe:2.3:a:apache:arrow:${ARROW_VERSION}:*:*:*:*:*:*:*|Apache-2.0" \
        "thrift|${THRIFT_VERSION}|pkg:generic/apache/thrift@${THRIFT_VERSION}|cpe:2.3:a:apache:thrift:${THRIFT_VERSION}:*:*:*:*:*:*:*|Apache-2.0" \
        "xsimd|${XSIMD_VERSION}|pkg:github/xtensor-stack/xsimd@${XSIMD_VERSION}||BSD-3-Clause" \
        "simdjson|${SIMDJSON_VERSION}|pkg:github/simdjson/simdjson@v${SIMDJSON_VERSION}|cpe:2.3:a:simdjson:simdjson:${SIMDJSON_VERSION}:*:*:*:*:*:*:*|Apache-2.0" && \
    rm -rf thrift arrow && \
    echo "${BASE_DIR}/lib" > /etc/ld.so.conf.d/geosgb.conf && \
    ldconfig

# Configure Python virtualenv: pip, setuptools, wheel (GDAL bindings build) and numpy, pinned with
# hashes in requirements/venv.txt (generated from requirements/venv.in)
RUN --mount=type=bind,source=requirements/venv.txt,target=/tmp/venv-requirements.txt \
    python3 -m venv --prompt geosgb ${BASE_DIR}/venv && \
    ${BASE_DIR}/venv/bin/pip install --no-cache-dir --require-hashes -r /tmp/venv-requirements.txt

# Compile and install GDAL
ARG GDAL_VERSION=3.12.4
# SHA256 of gdal-${GDAL_VERSION}.tar.gz, taken from a tarball whose .sig was verified against the
# GPG key published in GDAL's docs (doc/source/download.rst, fingerprint 7B130E955B44D87CCE2765F0DBD81FF52EC2A42A)
ARG GDAL_SHA256=68844ae29557b7efae4292c3b4cb3a3b8a79d14b765b89c5a7b17cbae7fa715a

RUN --mount=type=bind,source=sbom/cyclonedx.py,target=/tmp/cyclonedx.py \
    GDAL_URL=https://download.osgeo.org/gdal/${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz && \
    wget -q "${GDAL_URL}" && \
    echo "${GDAL_SHA256}  gdal-${GDAL_VERSION}.tar.gz" | sha256sum -c - && \
    # keep the source tree in the image for debugging and building GDAL-dependent code
    mkdir -p "${BASE_DIR}/src" && \
    tar -zxf "gdal-${GDAL_VERSION}.tar.gz" -C "${BASE_DIR}/src" && \
    rm "gdal-${GDAL_VERSION}.tar.gz" && \
    GDAL_DIR=${BASE_DIR}/src/gdal-${GDAL_VERSION} && \
    mkdir -p "$GDAL_DIR/build" && \
    ( cd "$GDAL_DIR/build" && \
    cmake \
        -DCMAKE_CXX_FLAGS="-Wno-psabi ${HARDENING_CFLAGS}" \
        -DCMAKE_C_FLAGS="-Wno-psabi ${HARDENING_CFLAGS}" \
        -DCMAKE_SHARED_LINKER_FLAGS="${HARDENING_LDFLAGS}" \
        -DCMAKE_EXE_LINKER_FLAGS="${HARDENING_LDFLAGS}" \
        -DCMAKE_MODULE_LINKER_FLAGS="${HARDENING_LDFLAGS}" \
        # debug symbols for the devel stage (stripped by staging) with the same -O3 as Release
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_C_FLAGS_RELWITHDEBINFO="-O3 -g -DNDEBUG" \
        -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-O3 -g -DNDEBUG" \
        -DCMAKE_INSTALL_PREFIX=${BASE_DIR} \
        # Arrow/Parquet installed in ${BASE_DIR} by the previous step
        -DCMAKE_PREFIX_PATH=${BASE_DIR} \
        -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF \
        -DOGR_BUILD_OPTIONAL_DRIVERS=OFF \
        -DOracle_ROOT="$(find "${BASE_DIR}/oracle" -name 'instantclient*' -type d -print -quit)" \
        # fail the configure step if a dependency is missing, instead of silently skipping the driver
        -DGDAL_USE_ORACLE=ON \
        -DGDAL_USE_ARROW=ON \
        -DGDAL_USE_PARQUET=ON \
        -DOGR_ENABLE_DRIVER_OCI=ON \
        -DOGR_ENABLE_DRIVER_ARROW=ON \
        -DOGR_ENABLE_DRIVER_PARQUET=ON \
        -DOGR_ENABLE_DRIVER_OPENFILEGDB=ON \
        # PostGIS (vector + raster); the PG driver depends on PGDump
        -DGDAL_USE_POSTGRESQL=ON \
        -DOGR_ENABLE_DRIVER_PGDUMP=ON \
        -DOGR_ENABLE_DRIVER_PG=ON \
        -DGDAL_ENABLE_DRIVER_POSTGISRASTER=ON \
        # GeoPackage (vector + raster); depends on the SQLite driver, raster tiles use PNG/JPEG
        -DGDAL_USE_SQLITE3=ON \
        -DOGR_ENABLE_DRIVER_SQLITE=ON \
        -DOGR_ENABLE_DRIVER_GPKG=ON \
        -DGDAL_ENABLE_DRIVER_PNG=ON \
        -DGDAL_ENABLE_DRIVER_JPEG=ON \
        # OGC web services (WMS, WFS, WCS, OGC API); WMS builds against the RAW driver,
        # WFS parses responses with the GML driver, OGC API vector tiles use the MVT driver
        -DGDAL_USE_CURL=ON \
        -DGDAL_ENABLE_DRIVER_RAW=ON \
        -DGDAL_ENABLE_DRIVER_WMS=ON \
        -DGDAL_ENABLE_DRIVER_WCS=ON \
        -DGDAL_ENABLE_DRIVER_OGCAPI=ON \
        -DOGR_ENABLE_DRIVER_WFS=ON \
        -DOGR_ENABLE_DRIVER_OAPIF=ON \
        -DOGR_ENABLE_DRIVER_GML=ON \
        -DOGR_ENABLE_DRIVER_MVT=ON \
        # Elasticsearch (vector, over HTTP via curl)
        -DOGR_ENABLE_DRIVER_ELASTIC=ON \
        # KML (expat-based) and LIBKML (KML + KMZ read/write)
        -DGDAL_USE_EXPAT=ON \
        -DGDAL_USE_LIBKML=ON \
        -DOGR_ENABLE_DRIVER_KML=ON \
        -DOGR_ENABLE_DRIVER_LIBKML=ON \
        -DBUILD_PYTHON_BINDINGS=ON \
        -DPython_EXECUTABLE=${BASE_DIR}/venv/bin/python \
        -DGDAL_PYTHON_INSTALL_PREFIX=${BASE_DIR}/venv \
    ..  && \
    # the Python extensions are built by setuptools (setup.py build_ext), which takes CFLAGS/CXXFLAGS from the
    # environment *instead of* Python's own flags (-O3 ...), so both are passed; CMake ignores these variables,
    # its CMAKE_*_FLAGS are set above
    PY_CFLAGS=$(${BASE_DIR}/venv/bin/python -c 'import sysconfig; print(sysconfig.get_config_var("CFLAGS"))') && \
    CFLAGS="${PY_CFLAGS} ${HARDENING_CFLAGS}" CXXFLAGS="${PY_CFLAGS} ${HARDENING_CFLAGS}" LDFLAGS="${HARDENING_LDFLAGS}" \
        cmake --build . --parallel "$(nproc)" --target install ) && \
    rm -rf "$GDAL_DIR/build" && \
    ldconfig && \
    python3 /tmp/cyclonedx.py "${BASE_DIR}/share/sbom/gdal.cdx.json" \
        "gdal|${GDAL_VERSION}|pkg:generic/osgeo/gdal@${GDAL_VERSION}|cpe:2.3:a:osgeo:gdal:${GDAL_VERSION}:*:*:*:*:*:*:*|MIT"

# venv first, so python/pip in the shell resolve to the virtualenv
ENV GDAL_DATA=${BASE_DIR}/share/gdal \
    VIRTUAL_ENV=${BASE_DIR}/venv \
    PATH=${BASE_DIR}/venv/bin:${BASE_DIR}/bin:$PATH

# nss_wrapper, used by docker-entrypoint.d/10-enable-nss-wrapper.sh for arbitrary UIDs
RUN apt-get -y update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        libnss-wrapper && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/*

# the python base image ships its own pip in /usr/local, outdated and unused (pip resolves to the venv);
# ensurepip's bundled wheel stays, so `python3 -m venv` still works in derived images
RUN /usr/local/bin/python3 -m pip uninstall -y -q pip

# Derived images drop *.sh scripts in /docker-entrypoint.d: executable ones run, the others are sourced
COPY --chmod=755 docker-entrypoint.sh /docker-entrypoint.sh

# explicit mode per script: 644 = sourced (needed so nss_wrapper's exports reach the command);
# the directory is created first because COPY --chmod would also apply 644 to it (not traversable by non-root)
RUN mkdir -p /docker-entrypoint.d
COPY --chmod=644 docker-entrypoint.d/10-enable-nss-wrapper.sh /docker-entrypoint.d/

ENTRYPOINT ["/docker-entrypoint.sh"]

# setting ENTRYPOINT resets the CMD inherited from the python image
CMD ["python3"]

SHELL ["/bin/sh", "-c"]


# Prepare ${BASE_DIR} for release: drop build-only files, strip debug symbols
# and resolve the Debian runtime packages needed by the GDAL binaries
FROM devel AS staging

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG BASE_DIR

RUN GDAL_ELF_DIRS=("${BASE_DIR}/bin" "${BASE_DIR}/lib" ${BASE_DIR}/venv/lib/python*/site-packages/osgeo) && \
    # build-only files (sources, headers, CMake/pkg-config files, static libs, Oracle SDK)
    rm -rf "${BASE_DIR}/src" "${BASE_DIR}/include" "${BASE_DIR}/lib/cmake" "${BASE_DIR}/lib/pkgconfig" && \
    find "${BASE_DIR}/lib" -name '*.a' -delete && \
    find "${BASE_DIR}/oracle" -mindepth 2 -maxdepth 2 -type d -name sdk -exec rm -rf {} + && \
    # debug symbols (GDAL is built with RelWithDebInfo); non-ELF files are ignored
    { find "${GDAL_ELF_DIRS[@]}" -type f \( -name '*.so*' -o -perm -u+x \) -exec strip --strip-debug {} + 2> /dev/null || true; } && \
    # shared libraries linked by GDAL (transitively, including the Oracle client)
    LDD_OUT=$(find "${GDAL_ELF_DIRS[@]}" -type f \( -name '*.so*' -o -perm -u+x \) -exec ldd {} + 2> /dev/null || true) && \
    if grep 'not found' <<< "$LDD_OUT" >&2; then exit 1; fi && \
    # map them to the Debian packages that own them (libs under ${BASE_DIR} and /usr/local are copied as is)
    awk '$2 == "=>" && $3 ~ /^\// {print $3}' <<< "$LDD_OUT" | xargs realpath | sort -u | \
        grep -v -e "^${BASE_DIR}/" -e '^/usr/local/' | \
        while read -r LIB; do dpkg -S "$LIB" | cut -d: -f1; done | \
        sort -u > /tmp/runtime-packages.txt && \
    test -s /tmp/runtime-packages.txt


# ${BASE_DIR} without the venv (Python bindings, numpy and the Python utilities such as gdal_calc.py),
# for the nopy image; removed in its own stage so the files never reach a layer of nopy
FROM staging AS staging-nopy

ARG BASE_DIR

RUN rm -rf "${BASE_DIR}/venv"


# Same GDAL runtime as release, without Python: debian slim base and no venv. Defined before release,
# which stays the last stage (default target)
FROM debian:${DEBIAN_VERSION}-slim AS nopy

ARG BASE_DIR

COPY --from=staging /etc/ld.so.conf.d/oracle.conf /etc/ld.so.conf.d/geosgb.conf /etc/ld.so.conf.d/

# same runtime packages as release; the python slim image brings ca-certificates, netbase and tzdata,
# which ldd does not list (data, not linked libraries) and GDAL needs for HTTPS (cURL), services and time zones.
# This stage is never cached in CI (no-cache-filters: nopy), so every build gets the current Debian fixes
RUN --mount=type=bind,from=staging,source=/tmp/runtime-packages.txt,target=/tmp/runtime-packages.txt \
    apt-get -y update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade && \
    xargs -a /tmp/runtime-packages.txt \
        apt-get install -y --no-install-recommends --no-install-suggests && \
    # nss_wrapper is preloaded by the entrypoint, not linked by GDAL, so ldd does not list it
    apt-get install -y --no-install-recommends --no-install-suggests \
        ca-certificates netbase tzdata libnss-wrapper && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/*

COPY --from=staging-nopy ${BASE_DIR} ${BASE_DIR}

# Oracle client looks for libaio.so.1 (Debian trixie ships libaio.so.1t64)
RUN ARCH=$(uname -m) && \
    ln -s "$(find "/usr/lib/$ARCH-linux-gnu" -name 'libaio.so.1*' -type f -print -quit)" "/usr/lib/$ARCH-linux-gnu/libaio.so.1" && \
    ldconfig

ENV GDAL_DATA=${BASE_DIR}/share/gdal \
    PATH=${BASE_DIR}/bin:$PATH

# same entrypoint as devel and release (COPY --from keeps the modes set there)
COPY --from=staging /docker-entrypoint.sh /docker-entrypoint.sh
COPY --from=staging /docker-entrypoint.d /docker-entrypoint.d

ENTRYPOINT ["/docker-entrypoint.sh"]

# setting ENTRYPOINT resets the CMD inherited from the debian image
CMD ["bash"]


FROM python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION} AS release

ARG BASE_DIR

COPY --from=staging /etc/ld.so.conf.d/oracle.conf /etc/ld.so.conf.d/geosgb.conf /etc/ld.so.conf.d/

# upgrade applies the Debian fixes released after the python base image was built; this stage is never
# cached in CI (no-cache-filters: release), so every build gets them
RUN --mount=type=bind,from=staging,source=/tmp/runtime-packages.txt,target=/tmp/runtime-packages.txt \
    apt-get -y update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade && \
    xargs -a /tmp/runtime-packages.txt \
        apt-get install -y --no-install-recommends --no-install-suggests && \
    # nss_wrapper is preloaded by the entrypoint, not linked by GDAL, so ldd does not list it
    apt-get install -y --no-install-recommends --no-install-suggests \
        libnss-wrapper && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/* && \
    # system pip of the python base image, outdated and unused (same as devel)
    /usr/local/bin/python3 -m pip uninstall -y -q pip

COPY --from=staging ${BASE_DIR} ${BASE_DIR}

# Oracle client looks for libaio.so.1 (Debian trixie ships libaio.so.1t64)
RUN ARCH=$(uname -m) && \
    ln -s "$(find "/usr/lib/$ARCH-linux-gnu" -name 'libaio.so.1*' -type f -print -quit)" "/usr/lib/$ARCH-linux-gnu/libaio.so.1" && \
    ldconfig

ENV GDAL_DATA=${BASE_DIR}/share/gdal \
    VIRTUAL_ENV=${BASE_DIR}/venv \
    PATH=${BASE_DIR}/venv/bin:${BASE_DIR}/bin:$PATH

# same entrypoint as devel (COPY --from keeps the modes set there)
COPY --from=staging /docker-entrypoint.sh /docker-entrypoint.sh
COPY --from=staging /docker-entrypoint.d /docker-entrypoint.d

ENTRYPOINT ["/docker-entrypoint.sh"]

# setting ENTRYPOINT resets the CMD inherited from the python image
CMD ["python3"]