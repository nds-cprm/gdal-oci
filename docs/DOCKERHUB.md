# GDAL

Base images with **GDAL 3.12 built from source**, Python bindings, Apache Arrow/Parquet (with **pyarrow** built against the same libraries) and the **Oracle Instant Client**, meant as a foundation for geospatial application images. Maintained by the Geological Survey of Brazil (SGB/CPRM).

- **Three images from one build:** `devel` to compile, `release-py` to run Python applications, `release-nopy` for the GDAL utilities and C/C++ applications.
- **Selected drivers:** Oracle Spatial, PostGIS, GeoPackage, Parquet/Arrow, OpenFileGDB, KML, OGC services and more.
- **Up to date:** rebuilt every week with the Debian and Python security fixes.
- **Verified sources:** every download is checked against a pinned SHA-256, and the Python packages are installed with `--require-hashes`.
- **Hardened build:** stack protector, `_FORTIFY_SOURCE=3`, stack clash protection and full RELRO.
- **Scanned:** no tag is published if the build has a **critical vulnerability with a fix available**. CVEs that do not apply are declared in an OpenVEX document.
- **Arbitrary UIDs** (OpenShift, `--user`) and read-only root filesystems are supported.
- **amd64 and arm64**, with SBOM and provenance attestations.

Source code, examples and documentation: <https://github.com/nds-cprm/gdal-oci>

## Images and tags

| | `devel` | `release-py` | `release-nopy` |
|---|---|---|---|
| **Tag** | `<gdal>-py<python>-devel` | `<gdal>-py<python>` | `<gdal>-nopy` |
| **Purpose** | Compile against GDAL and debug | Base for application images (production) | GDAL utilities and C/C++ applications, without Python |
| **Base** | `python:3.12-trixie` | `python:3.12-slim-trixie` | `debian:trixie-slim` |
| **Size** | ~2.0 GB | ~620 MB | ~450 MB |
| **Python** | Virtualenv with `osgeo`, numpy and pyarrow | Same as `devel` | None |
| **Extras** | Compiler, `cmake`, `swig`, `-dev` packages, headers and GDAL source code | Runtime only | Runtime only |

Each tag starts with the **GDAL version** (`<gdal>`, the full version), followed by suffixes that select the image:

| Suffix | Contents |
|---|---|
| `-py<python>` | `release-py`, with the Python `major.minor` version of the image. |
| `-py<python>-devel` | `devel`, with the same Python. |
| `-nopy` | `release-nopy`, without Python. |
| `-YYYYMMDD` | Appended to any of the above: one specific build, identified by its date (UTC). Never overwritten: a second build on the same day gets `.2`, `.3`... Use it, preferably with its digest, for reproducible builds. |

- The tags without a date are moving: they always point to the latest weekly build.
- The three images of a version are **always built and published together**. When combining them, use tags from the same build (the same date).
- The other versions in the image (Debian, Arrow, Oracle Instant Client, numpy) are not part of the tag.
- The available versions are listed in the Tags tab. Tags that do not follow this pattern are legacy images, not built by this project, and receive **no updates**. Do not use them in new projects.

## What is included

Everything lives in `/opt/geosgb`:

| Path | Contents |
|---|---|
| `/opt/geosgb/bin` | GDAL utilities (`gdalinfo`, `ogr2ogr`, `gdal_translate`, the `gdal` CLI…) |
| `/opt/geosgb/lib` | `libgdal.so` and the Arrow/Parquet libraries |
| `/opt/geosgb/share/gdal` | GDAL data (`GDAL_DATA`) |
| `/opt/geosgb/venv` | Python virtualenv with `osgeo`, numpy and pyarrow (not in `release-nopy`) |
| `/opt/geosgb/oracle` | Oracle Instant Client 19 (basiclite; the SDK is only in `devel`) |

| Category | Drivers |
|---|---|
| Databases | Oracle Spatial (`OCI`), PostGIS vector and raster, `SQLite`, `Elasticsearch` |
| Vector files | `GPKG`, `OpenFileGDB`, `Parquet`, `Arrow`, `KML`, `LIBKML`, `GML`, `MVT`, `GeoJSON`, `ESRI Shapefile` |
| Raster files | `GTiff`, `COG`, `GPKG`, `PNG`, `JPEG`, `VRT` |
| OGC services | `WMS`, `WFS`, `WCS`, `OGCAPI`, `OAPIF` |
| Remote access | `/vsicurl/` (HTTP/HTTPS) |

Check with `docker run --rm docker.io/ndscprm/gdal:<gdal>-py<python> ogrinfo --formats`.

Other versions: Debian trixie, PROJ 9.6 and GEOS 3.13 (Debian packages), Apache Arrow 26 (built from source, with an up-to-date Thrift statically linked into Parquet) and numpy 2.x.

## Using `release-py` as a base

The `/opt/geosgb/venv` virtualenv is **active by default**: `python` and `pip` resolve to it through the `PATH`.

```dockerfile
FROM docker.io/ndscprm/gdal:<gdal>-py<python>

WORKDIR /app
COPY requirements.txt .
RUN python -c 'import pyarrow; print("pyarrow==" + pyarrow.__version__)' > /tmp/constraints.txt && \
    pip install --no-cache-dir -c /tmp/constraints.txt -r requirements.txt

COPY . .
CMD ["python", "app.py"]
```

- **Do not install `GDAL` from PyPI.** It would replace the bindings built with the drivers above.
- **Do not install `pyarrow` from PyPI.** The image's pyarrow uses the same Arrow C++ as GDAL, so data flows between them through the Arrow C stream interface without per-feature conversion. The constraint above makes `pip install` fail instead of silently replacing it.
- **numpy:** any version from 1.25 on works with the bindings.
- **Libraries that depend on GDAL** (`fiona`, `rasterio`): the PyPI wheels bundle their own GDAL. To use the image's GDAL, build them from source in `devel` and copy the venv (see `examples/fiona` in the repository).

## Building in `devel`, running in `release-py` or `release-nopy`

`devel` ships `gdal-config`, the CMake package (`-DCMAKE_PREFIX_PATH=/opt/geosgb`) and pkg-config files. Build there and copy only the result:

```dockerfile
FROM docker.io/ndscprm/gdal:<gdal>-py<python>-devel AS build
COPY . /src
RUN cmake -S /src -B /src/build -DCMAKE_PREFIX_PATH=/opt/geosgb && \
    cmake --build /src/build

FROM docker.io/ndscprm/gdal:<gdal>-py<python>   # or <gdal>-nopy
COPY --from=build /src/build/app /usr/local/bin/
CMD ["app"]
```

Python packages with native extensions are installed into the venv in `devel`, and the whole venv is copied:

```dockerfile
FROM docker.io/ndscprm/gdal:<gdal>-py<python>-devel AS build
RUN pip install --no-cache-dir --no-binary fiona "fiona==1.10.1"

FROM docker.io/ndscprm/gdal:<gdal>-py<python>
COPY --from=build /opt/geosgb/venv /opt/geosgb/venv
```

## Using `release-nopy`

The same GDAL, drivers and entrypoint, without Python. The GDAL utilities written in Python (`gdal_calc.py`, `gdal2tiles.py`…) are not included; many have an equivalent in the `gdal` CLI (`gdal raster calc`, `gdal raster tile`).

```sh
docker run --rm -v "$PWD:/data" -w /data docker.io/ndscprm/gdal:<gdal>-nopy \
  ogr2ogr -f Parquet output.parquet input.gpkg
```

## Startup scripts (`/docker-entrypoint.d`)

The entrypoint runs the `*.sh` files in `/docker-entrypoint.d` in alphabetical order before the container command, following the convention of the official PostgreSQL image:

| File mode | What happens | Use for |
|---|---|---|
| Executable (`755`) | Run in a separate process | Actions: waiting for a service, creating directories |
| Not executable (`644`) | Sourced by the entrypoint; exported variables reach the command | Setting environment variables at startup |

- Always set the mode with `COPY --chmod`.
- Do not use `exit` in sourced scripts: it ends the container before the command runs.
- Log to stderr: stdout belongs to the container command.
- A failing script stops the container from starting. `ENTRYPOINT_QUIET_LOGS=1` silences the entrypoint logs.
- If a derived image sets its own `ENTRYPOINT`, chain the original one: `ENTRYPOINT ["/docker-entrypoint.sh", "my-entrypoint.sh"]`.

## Arbitrary UIDs and read-only root

When the container runs with a UID that is not in `/etc/passwd` (OpenShift, `--user 12345:0`), an nss_wrapper creates a virtual user named after `USER_NAME` (default `sgb`) and sets `HOME=/tmp` if the inherited `HOME` is empty or `/`. With a read-only root filesystem, `/tmp` must be writable:

```sh
docker run --read-only --tmpfs /tmp --user 12345:0 \
  docker.io/ndscprm/gdal:<gdal>-py<python> python -c "import getpass; print(getpass.getuser())"
```

On Kubernetes and OpenShift, use `readOnlyRootFilesystem: true` with an `emptyDir` on `/tmp`.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `GDAL_DATA` | `/opt/geosgb/share/gdal` | GDAL data. |
| `VIRTUAL_ENV` | `/opt/geosgb/venv` | Active venv (not set in `release-nopy`). |
| `PATH` | `/opt/geosgb/venv/bin:/opt/geosgb/bin:…` | Venv and GDAL utilities first. |
| `USER_NAME` | `sgb` | Name of the virtual user created by the nss_wrapper. |
| `ENTRYPOINT_QUIET_LOGS` | empty | Any value silences the entrypoint logs. |

GDAL configuration options (`GDAL_HTTP_*`, `CPL_*`, `OGR_*`…) work as environment variables as usual.

## Opening user-supplied files

For GDAL, **opening a file already processes it**. This image enables drivers that reach the network (WMS, WCS, WFS, OGC API, Elasticsearch, `/vsicurl/`) and drivers that open other datasets (VRT), so a malicious upload can make the server request internal URLs (SSRF). Applications that open files or paths coming from users should:

1. Restrict the drivers when opening: `gdal.OpenEx(path, gdal.OF_VECTOR, allowed_drivers=["GPKG", "GeoJSON"])`.
2. Disable the drivers they do not use with `GDAL_SKIP` (for example `ENV GDAL_SKIP="VRT WMS WCS WFS OAPIF OGCAPI Elasticsearch"`).
3. Never pass a user string to GDAL as a path, utility option or configuration option.
4. Restrict the container's outbound network, especially to the internal network and cloud metadata endpoints.
5. Check raster dimensions before reading, and limit memory, CPU and processing time.

See GDAL's [security considerations](https://gdal.org/en/stable/user/security.html).

## Derived images

- [`ndscprm/mapserver`](https://hub.docker.com/r/ndscprm/mapserver): MapServer as a FastCGI server.
- [`ndscprm/mapproxy`](https://hub.docker.com/r/ndscprm/mapproxy): MapProxy on uWSGI.
- [`ndscprm/pygeoapi`](https://hub.docker.com/r/ndscprm/pygeoapi): pygeoapi on uWSGI.

They are rebuilt automatically every time these images are published.

## License

Apache-2.0. GDAL is released under the MIT license, and the Oracle Instant Client under the Oracle Free Use Terms and Conditions. As with any container image, these images also contain software under other licenses (Debian, Python, Apache Arrow and their dependencies), and it is the user's responsibility to make sure their use complies with them.
