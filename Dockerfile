ARG PYTHON_VERSION=3.12
ARG DEBIAN_VERSION=trixie

ARG BASE_DIR=/opt/geosgb


FROM python:${PYTHON_VERSION}-${DEBIAN_VERSION} AS devel

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG BASE_DIR

# Install dependencies
RUN apt-get -y update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        build-essential \
        cmake \
        gdb \
        ca-certificates \
        lsb-release \
        gnupg \
        unzip \
        wget && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/*

# Oracle
# SHA256 from Oracle download pages (linux-x86-64 / linux-arm-aarch64)
# v19.32.0.0.0
ARG ORACLE_BASICLITE_SHA256_X64=16947fc0fa55b861903aad6f9d2ddee7b4fedaf789a175ee36b46b82ec64fcbd
ARG ORACLE_SDK_SHA256_X64=1698b3be6dde8b7e90501a62122cb9c160c712eb709deb7129d915a504b76158

ARG ORACLE_BASICLITE_SHA256_ARM64=2c7c657b1e77b95a969e70f9af816b5e88f40047249c820936aa87a126d8e4f4
ARG ORACLE_SDK_SHA256_ARM64=be3b37817943102cb051fad80f5dc821821cf1616ffd0983c2ded81621c760d3

WORKDIR /tmp

RUN apt-get -y update && \
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
    wget -qO oracle.zip "https://download.oracle.com/otn_software/linux/instantclient/1932000/instantclient-basiclite-linux.$ARCH-19.32.0.0.0dbru.zip" && \
    wget -qO oracle-sdk.zip "https://download.oracle.com/otn_software/linux/instantclient/1932000/instantclient-sdk-linux.$ARCH-19.32.0.0.0dbru.zip" && \
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
    ldconfig

# Install GDAL dependencies, with Oracle and Arrow/Parquet support
# Fingerprints (space separated) of the keys allowed to sign the Arrow apt repository,
# taken from https://downloads.apache.org/arrow/KEYS
# Apache Arrow <major>.<minor>: build installs the latest <major>.<minor>.* and release the matching runtime libs
ARG APACHE_ARROW_VERSION=26.0
ARG APACHE_ARROW_SIGNER_FINGERPRINTS=7BD1A9A50E4F701BCBFD90EF9E922B2D60E9FD1C

RUN test -n "${APACHE_ARROW_SIGNER_FINGERPRINTS}" && \
    # keyring with only the pinned keys
    wget -qO arrow-KEYS https://downloads.apache.org/arrow/KEYS && \
    GNUPGHOME=$(mktemp -d) && \
    export GNUPGHOME && \
    gpg --batch --quiet --import arrow-KEYS && \
    for FPR in ${APACHE_ARROW_SIGNER_FINGERPRINTS}; do gpg --batch --list-keys "$FPR" > /dev/null || exit 1; done && \
    gpg --batch --export ${APACHE_ARROW_SIGNER_FINGERPRINTS} > /usr/share/keyrings/apache-arrow.gpg && \
    rm -rf "$GNUPGHOME" arrow-KEYS && \
    # repository
    printf "Types: deb\nURIs: https://packages.apache.org/artifactory/arrow/%s/\nSuites: %s\nComponents: main\nSigned-By: /usr/share/keyrings/apache-arrow.gpg\n" \
        "$(lsb_release --id --short | tr '[:upper:]' '[:lower:]')" "$(lsb_release --codename --short)" \
        > /etc/apt/sources.list.d/apache-arrow.sources && \
    # pin every Arrow/Parquet package (including indirect deps like libarrow-acero-dev) to <major>.<minor>.*
    [[ "${APACHE_ARROW_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]] && \
    printf "Package: libarrow* libparquet*\nPin: version %s.*\nPin-Priority: 1001\n" "${APACHE_ARROW_VERSION}" \
        > /etc/apt/preferences.d/apache-arrow && \
    apt-get -y update && \
    apt-get install -y --no-install-recommends --no-install-suggests \
        swig \
        libarrow-dev \
        libarrow-compute-dev \
        libarrow-dataset-dev \
        libcurl4-openssl-dev \
        libexpat1-dev \
        libsfcgal-dev \
        libgeos-dev \
        libgeotiff-dev \
        libjson-c-dev \
        libkml-dev \
        # libmariadb-dev \
        libmuparser-dev \
        libparquet-dev \
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

# Configure Python virtualenv
# GDAL bindings built against numpy 2 also run with numpy 1.x (the reverse fails at import)
ARG NUMPY_VERSION=2.5.4

RUN python3 -m venv --prompt geosgb ${BASE_DIR}/venv && \
    ${BASE_DIR}/venv/bin/pip install --upgrade pip setuptools wheel && \
    ${BASE_DIR}/venv/bin/pip install "numpy==${NUMPY_VERSION}"

# Compile and install GDAL
ARG GDAL_VERSION=3.12.4
# SHA256 of gdal-${GDAL_VERSION}.tar.gz, taken from a tarball whose .sig was verified against the
# GPG key published in GDAL's docs (doc/source/download.rst, fingerprint 7B130E955B44D87CCE2765F0DBD81FF52EC2A42A)
ARG GDAL_SHA256=68844ae29557b7efae4292c3b4cb3a3b8a79d14b765b89c5a7b17cbae7fa715a

RUN GDAL_URL=https://download.osgeo.org/gdal/${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz && \
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
        -DCMAKE_CXX_FLAGS="-Wno-psabi" \
        -DCMAKE_C_FLAGS="-Wno-psabi" \
        # debug symbols for the devel stage (stripped by staging) with the same -O3 as Release
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_C_FLAGS_RELWITHDEBINFO="-O3 -g -DNDEBUG" \
        -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-O3 -g -DNDEBUG" \
        -DCMAKE_INSTALL_PREFIX=${BASE_DIR} \
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
    cmake --build . --target install ) && \
    rm -rf "$GDAL_DIR/build" && \
    echo "${BASE_DIR}/lib" > /etc/ld.so.conf.d/geosgb.conf && \
    ldconfig

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


FROM python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION} AS release

ARG BASE_DIR

# Arrow/Parquet runtime libs come from the Apache Arrow repository, pinned to the same version used in the build
COPY --from=staging /usr/share/keyrings/apache-arrow.gpg /usr/share/keyrings/
COPY --from=staging /etc/apt/sources.list.d/apache-arrow.sources /etc/apt/sources.list.d/
COPY --from=staging /etc/apt/preferences.d/apache-arrow /etc/apt/preferences.d/
COPY --from=staging /etc/ld.so.conf.d/oracle.conf /etc/ld.so.conf.d/geosgb.conf /etc/ld.so.conf.d/

RUN --mount=type=bind,from=staging,source=/tmp/runtime-packages.txt,target=/tmp/runtime-packages.txt \
    apt-get -y update && \
    xargs -a /tmp/runtime-packages.txt \
        apt-get install -y --no-install-recommends --no-install-suggests && \
    # nss_wrapper is preloaded by the entrypoint, not linked by GDAL, so ldd does not list it
    apt-get install -y --no-install-recommends --no-install-suggests \
        libnss-wrapper && \
    apt-get -y autoremove && \
    rm -rf /var/lib/apt/lists/*

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