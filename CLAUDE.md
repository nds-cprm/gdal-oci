# CLAUDE.md

Este arquivo orienta o Claude Code (claude.ai/code) ao trabalhar neste repositório.

## Visão geral

Imagem Docker base com **GDAL compilado a partir do código-fonte**, com suporte a **Oracle (OCI)**, **Apache Arrow/Parquet**, PostGIS, Elasticsearch, GeoPackage, OpenFileGDB, COG, KML/KMZ e serviços OGC (WMS/WFS/WCS/OGC API), mais os bindings Python do GDAL instalados em um virtualenv. Tudo é instalado sob `BASE_DIR=/opt/geosgb`.

O repositório contém o [README.md](README.md) (documentação para quem usa as imagens `devel`/`release` como base; manter em sincronia com o Dockerfile), o [Dockerfile](Dockerfile), o [docker-entrypoint.sh](docker-entrypoint.sh), os scripts de inicialização em [docker-entrypoint.d/](docker-entrypoint.d/), os exemplos de imagens derivadas em [examples/](examples/) (cada subdiretório com Dockerfile e README; a imagem base entra por `GDAL_IMAGE`/`GDAL_TAG`, então dá para testar com tags locais via `--build-arg`), a [LICENSE](LICENSE) (Apache 2.0) e o CI em [.github/](.github/).

Esta imagem servirá de base para outras imagens de aplicação Python com GDAL

## CI ([docker-image.yml](.github/workflows/docker-image.yml))

Disparado manualmente (`workflow_dispatch`; push/PR/schedule comentados). Job `build` por arquitetura em runner nativo (`amd64` em `ubuntu-22.04`, `arm64` em `ubuntu-24.04-arm`): build do `devel` e depois do `release` no mesmo builder (as duas saem do mesmo build do GDAL), push só por digest, cache GHA com `cache-to` apenas no `release` (o `mode=max` dele já cobre todos os estágios). Em seguida roda [smoke-test.sh](.github/scripts/smoke-test.sh) nas duas imagens; se falhar, o job `merge` não roda e nenhuma tag é criada. O `merge` lê `GDAL_VERSION` e `PYTHON_VERSION` dos `ARG` do Dockerfile, cria as tags multi-arquitetura `<gdal>-py<python>` e `<gdal>-py<python>-devel` e roda o Docker Scout (CVEs) no `release`, enviando o SARIF para o code scanning. Requer os secrets `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN`.

O smoke test também roda localmente: `sh .github/scripts/smoke-test.sh <imagem>`. Ele confere versões, a lista de drivers habilitados, escrita/leitura (COG, GPKG, KMZ, Parquet), bindings Python e o nss_wrapper com `--user 12345:0`. **Ao habilitar ou remover um driver no Dockerfile, atualizar `RASTER_DRIVERS`/`VECTOR_DRIVERS` no script.**

## Build

O último estágio (`release`) é o alvo padrão; use `--target devel` para a imagem de desenvolvimento.

```bash
docker build --target devel -t docker.io/ndscprm/gdal:3.12.4-py3.12-devel .
docker build -t docker.io/ndscprm/gdal:3.12.4-py3.12 .
# arquitetura específica (x64 e arm64 são suportadas)
docker buildx build --platform linux/arm64 -t docker.io/ndscprm/gdal:3.12.4-py3.12 .
```

**Política de tags** (repositório `docker.io/ndscprm/gdal`): `<GDAL_VERSION>-py<PYTHON_VERSION>` para o `release` e o mesmo com sufixo `-devel` para o `devel` (ex.: `3.12.4-py3.12` / `3.12.4-py3.12-devel`). As duas tags saem sempre do mesmo build: build do `devel` primeiro, depois do `release`, que reaproveita o cache. Debian, Arrow, Oracle e numpy não entram na tag. Ao mudar `GDAL_VERSION` ou `PYTHON_VERSION`, o nome das tags muda junto; os comandos de build/push estão no [README.md](README.md#build).

Verificação rápida após o build:

```bash
docker run --rm docker.io/ndscprm/gdal:3.12.4-py3.12 gdalinfo --version
docker run --rm docker.io/ndscprm/gdal:3.12.4-py3.12 ogrinfo --formats | grep -Ei 'oci|parquet|arrow'
docker run --rm docker.io/ndscprm/gdal:3.12.4-py3.12 /opt/geosgb/venv/bin/python -c "from osgeo import gdal; print(gdal.__version__)"
```

## Estrutura do Dockerfile

Três estágios:

- **`devel`** (`python:${PYTHON_VERSION}-${DEBIAN_VERSION}`): toolchain, headers, código-fonte do GDAL, símbolos de debug e `gdb`. Usado para depurar e compilar código dependente do GDAL.
- **`staging`** (`FROM devel`, descartável): remove de `${BASE_DIR}` os arquivos só de build (`src`, `include`, `lib/cmake`, `lib/pkgconfig`, `*.a`, SDK do Oracle), faz `strip --strip-debug` em `bin`, `lib` e nos módulos `osgeo` do venv, e gera `/tmp/runtime-packages.txt` com os pacotes Debian de runtime: roda `ldd` nos binários do GDAL (transitivo, inclui o Oracle client), resolve com `realpath` e mapeia com `dpkg -S`. O build falha se algum `ldd` der `not found` ou se uma lib não pertencer a nenhum pacote.
- **`release`** (`python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION}`): copia o keyring/sources/pin do Arrow e os `ld.so.conf.d` do staging, instala a lista de pacotes (bind mount, sem ficar na imagem), copia `${BASE_DIR}`, recria o symlink `libaio.so.1`, repete os `ENV` e define `ENTRYPOINT ["/docker-entrypoint.sh"]` + `CMD ["python3"]`. O venv funciona porque o python das imagens `python` e `python:*-slim` fica no mesmo caminho (`/usr/local/bin`).

Etapas do `devel`, em ordem:

1. **Ferramentas de build** — `build-essential`, `cmake`, `gdb`, `wget`, `gnupg`, etc. Para usar o `gdb` no container: `docker run --cap-add=SYS_PTRACE --security-opt seccomp=unconfined ...`.
2. **Oracle Instant Client 19.32** (basiclite + SDK) — baixado de `download.oracle.com`, validado por SHA256 por arquitetura (`ORACLE_*_SHA256_X64` / `_ARM64`), extraído em `${BASE_DIR}/oracle`. Cria o symlink `libaio.so.1` (Debian trixie só fornece `libaio.so.1t64`) e registra o diretório do client em `/etc/ld.so.conf.d/oracle.conf`.
3. **Dependências do GDAL** — inclui o repositório apt do Apache Arrow:
   - A chave é importada de `downloads.apache.org/arrow/KEYS`, mas o keyring só exporta as fingerprints listadas em `APACHE_ARROW_SIGNER_FINGERPRINTS`.
   - Todos os pacotes `libarrow*`/`libparquet*` são fixados em `${APACHE_ARROW_VERSION}.*` via `/etc/apt/preferences.d/apache-arrow` (formato obrigatório `<major>.<minor>`, validado por regex).
4. **Virtualenv Python** em `${BASE_DIR}/venv` com `numpy==${NUMPY_VERSION}` (necessário antes do GDAL para os bindings com suporte a arrays).
5. **GDAL** — baixado de `download.osgeo.org`, validado pelo SHA256 fixo em `GDAL_SHA256`, compilado com CMake (`RelWithDebInfo` fixo, com `-O3 -g -DNDEBUG` para manter a otimização do `Release`; símbolos ficam no `devel` e são removidos no `staging`; prefixo `${BASE_DIR}`, bindings Python compilados com o python do venv e instalados nele via `GDAL_PYTHON_INSTALL_PREFIX`). `${BASE_DIR}/lib` é registrado em `/etc/ld.so.conf.d/geosgb.conf`, pois os binários instalados não têm RPATH.
6. `ENV GDAL_DATA=${BASE_DIR}/share/gdal`, `VIRTUAL_ENV=${BASE_DIR}/venv` e `PATH` com `${BASE_DIR}/venv/bin` antes de `${BASE_DIR}/bin` (o `python`/`pip` do shell resolvem para o venv, sem precisar de `activate`).

## Build args

| Arg | Padrão | Observação |
|-----|--------|------------|
| `PYTHON_VERSION` | `3.12` | Tag da imagem `python` |
| `DEBIAN_VERSION` | `trixie` | Também define a suite do repo Arrow e o nome `libaio1t64` |
| `BASE_DIR` | `/opt/geosgb` | Declarado global e re-declarado no estágio |
| `ORACLE_*_SHA256_{X64,ARM64}` | v19.32.0.0.0 | Atualizar junto com a URL (`1932000` / `19.32.0.0.0dbru`) |
| `APACHE_ARROW_VERSION` | `26.0` | Apenas `<major>.<minor>` |
| `APACHE_ARROW_SIGNER_FINGERPRINTS` | uma fingerprint | Separadas por espaço; build falha se vazio ou ausente no KEYS |
| `NUMPY_VERSION` | `2.5.4` | Versão usada para compilar os bindings. Manter numpy 2: bindings compilados com numpy 2 rodam com 1.x e 2.x; compilados com 1.x quebram (`ImportError`) quando a imagem derivada instala numpy 2 |
| `GDAL_VERSION` | `3.12.4` | Atualizar junto com `GDAL_SHA256` |
| `GDAL_SHA256` | SHA256 do `gdal-3.12.4.tar.gz` | Ao trocar de versão: baixar o tarball e o `.sig`, verificar a assinatura com a chave GPG publicada em `doc/source/download.rst` do repositório do GDAL (fingerprint `7B130E955B44D87CCE2765F0DBD81FF52EC2A42A`) e só então gravar o `sha256sum` |

## Convenções

- `SHELL` usa `bash -o pipefail` no `devel` (volta para `/bin/sh -c` no final) e no `staging`; o `release` usa o shell padrão.
- Cada `RUN` com apt faz `update`, `install --no-install-recommends --no-install-suggests`, `autoremove` e apaga `/var/lib/apt/lists/*`.
- Todo download externo é verificado contra um valor fixado no Dockerfile (SHA256 do Oracle e do GDAL, fingerprint GPG do Arrow), nunca contra um checksum baixado do mesmo servidor. Ao atualizar uma versão, atualize também o checksum/fingerprint correspondente.
- A arquitetura do Oracle é derivada de `dpkg --print-architecture` (`amd64` → `x64`); arquiteturas diferentes de x64/arm64 abortam o build.

## Pontos de atenção (estado atual)

- **Drivers opcionais**: `GDAL_BUILD_OPTIONAL_DRIVERS=OFF` e `OGR_BUILD_OPTIONAL_DRIVERS=OFF` desativam todos os drivers opcionais; OCI, Arrow, Parquet, OpenFileGDB, PostGIS (`PG` + `PGDump`, e `POSTGISRASTER`) e GeoPackage (`GPKG` + `SQLite`, com `PNG`/`JPEG` para tiles raster) e serviços OGC (`WMS`, `WCS`, `OGCAPI`, `WFS`, `OAPIF`, mais `RAW` exigido no configure pelo WMS, e `GML` e `MVT` usados em runtime por WFS e OGC API Tiles) KML/KMZ (`KML` e `LIBKML`) e `Elasticsearch` (`ELASTIC`, via cURL) são habilitados explicitamente (`OGR_ENABLE_DRIVER_*`/`GDAL_ENABLE_DRIVER_*=ON`), com `GDAL_USE_ORACLE/ARROW/PARQUET/POSTGRESQL/SQLITE3/CURL/EXPAT/LIBKML=ON` para o configure falhar se a dependência não for encontrada. Qualquer outro driver opcional precisa ser adicionado da mesma forma.
- O código-fonte do GDAL é mantido de propósito em `${BASE_DIR}/src/gdal-${GDAL_VERSION}` (depuração e compilação de código dependente do GDAL); só o diretório `build/` é removido após o install. O `cd` para o build fica num subshell `( ... )`, então comandos após o `)` rodam em `/tmp`.
- Os pacotes de runtime do `release` não são listados à mão: vêm do `ldd` no `staging`. Ao adicionar um driver/dependência, não é preciso mexer no `release`. Pacotes que o GDAL só carrega em runtime sem linkar (ex.: dados) precisam ser adicionados explicitamente.
- **Entrypoint (`devel` e `release`)**: definido no `devel` (que o `staging` herda); o `release` copia `/docker-entrypoint.sh` e `/docker-entrypoint.d` do `staging` com `COPY --from`, que preserva os modos, para as duas imagens terem sempre o mesmo entrypoint. [docker-entrypoint.sh](docker-entrypoint.sh) (POSIX `sh`) percorre `/docker-entrypoint.d` em ordem léxica — mesmo modelo da imagem oficial do Postgres: `*.sh` com `+x` são executados, `*.sh` sem `+x` são carregados com `.` (variáveis exportadas chegam ao comando; `exit` neles, mesmo `exit 0`, interrompe o start), o resto é ignorado. Termina com `exec "$@"`. A permissão define o modo, então imagens derivadas devem usar `COPY --chmod`. Script com erro aborta o start (`set -e`). `ENTRYPOINT_QUIET_LOGS` silencia os logs. O `CMD ["python3"]` é explícito porque definir `ENTRYPOINT` zera o `CMD` herdado da imagem `python`; imagens derivadas que definirem só `CMD` continuam passando pelo entrypoint.
- **nss_wrapper (`devel` e `release`)**: o pacote `libnss-wrapper` é instalado explicitamente nos dois estágios (no `release`, à parte da lista do `ldd`, porque é carregado via `LD_PRELOAD` e não linkado) e [10-enable-nss-wrapper.sh](docker-entrypoint.d/10-enable-nss-wrapper.sh) (sem `+x`, portanto carregado com `.`) cria, quando o UID do container não existe no `/etc/passwd` (ex.: OpenShift, `--user`), um usuário virtual `${USER_NAME:-sgb}` em `/tmp/passwd` e exporta `NSS_WRAPPER_PASSWD`, `NSS_WRAPPER_GROUP` e `LD_PRELOAD=libnss_wrapper.so`. Nesse caso também exporta `HOME=/tmp` se o `HOME` for `/` (o Docker usa `/` para UID sem passwd) ou não gravável. A mensagem vai para o stderr e respeita `ENTRYPOINT_QUIET_LOGS` — scripts em `docker-entrypoint.d` nunca devem escrever no stdout, que é a saída do comando (ex.: `/vsistdout/`). Os scripts de `docker-entrypoint.d/` são copiados um a um com `COPY --chmod` explícito (o modo define executar vs. carregar, e não pode depender da permissão no disco); o diretório é criado antes com `RUN mkdir -p`, porque `COPY --chmod=644` também aplicaria `644` ao diretório e ele deixaria de ser acessível para usuários não root. Novo script no repositório = nova linha `COPY` no bloco do entrypoint do `devel` (o `release` recebe o diretório inteiro).
- `ENV` é repetido no `release` (não é herdado entre estágios com `FROM` diferentes); manter os dois em sincronia.
