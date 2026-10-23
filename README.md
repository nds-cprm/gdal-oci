# docker.io/ndscprm/gdal

> Documentação gerada por IA (Claude) e revisada por humanos 

Imagens Docker base com **GDAL 3.12.4 compilado do código-fonte**, bindings Python, Apache Arrow/Parquet e **Oracle Instant Client**, para servir de base a imagens de aplicações Python geoespaciais.

O mesmo [Dockerfile](Dockerfile) gera duas imagens:

| | `release` | `devel` |
|---|---|---|
| **Para quê** | Base de imagens de aplicação (produção) | Compilar código contra o GDAL e depurar |
| **Base** | `python:3.12-slim-trixie` | `python:3.12-trixie` |
| **Tamanho** | ~580 MB | ~2,4 GB |
| **GDAL** | Binários e bibliotecas, sem símbolos de debug | Binários com símbolos de debug, headers, CMake/pkg-config e código-fonte em `/opt/geosgb/src` |
| **Ferramentas** | Só o runtime | `build-essential`, `cmake`, `swig`, `gdb` e os pacotes `-dev` de todas as dependências |
| **Entrypoint** | [`/docker-entrypoint.sh`](docker-entrypoint.sh) + `/docker-entrypoint.d` | Igual ao `release` |
| **CMD** | `python3` | `python3` |

As duas imagens têm o mesmo GDAL compilado uma única vez (`-O3`). O `release` é o `devel` sem os símbolos de debug, sem os arquivos usados só no build e com apenas as bibliotecas de runtime que o GDAL realmente usa (detectadas com `ldd` durante o build).

## Imagens e tags

As imagens são publicadas em `docker.io/ndscprm/gdal`. A tag é formada pela **versão do GDAL** e pela **versão do Python**:

| Imagem | Tag | Exemplo |
|---|---|---|
| `release` | `<gdal>-py<python>` | `docker.io/ndscprm/gdal:3.12.4-py3.12` |
| `devel` | `<gdal>-py<python>-devel` | `docker.io/ndscprm/gdal:3.12.4-py3.12-devel` |
| `release` (build específico) | `<gdal>-py<python>-<AAAAMMDD>` | `docker.io/ndscprm/gdal:3.12.4-py3.12-20261026` |
| `devel` (build específico) | `<gdal>-py<python>-<AAAAMMDD>-devel` | `docker.io/ndscprm/gdal:3.12.4-py3.12-20261026-devel` |

- `<gdal>` é a versão completa do GDAL (`GDAL_VERSION`, ex.: `3.12.4`), e `<python>` é a versão `major.minor` do Python (`PYTHON_VERSION`, ex.: `3.12`).
- As duas tags de uma mesma versão são **sempre geradas e publicadas juntas, a partir do mesmo build**. Elas são feitas para serem usadas em conjunto (veja [Padrão recomendado](#padrão-recomendado-compilar-no-devel-rodar-no-release)).
- As imagens são **refeitas toda semana** para incorporar as correções de segurança do Debian e do Python. As tags `<gdal>-py<python>[-devel]` são móveis e sempre apontam para o build mais recente. As tags com data (`-<AAAAMMDD>`, em UTC) identificam um build e nunca são sobrescritas; um segundo build no mesmo dia recebe `.2`, `.3`, ... Para fixar exatamente um build, use a tag com data ou o digest (`docker.io/ndscprm/gdal:3.12.4-py3.12@sha256:…`).
- As outras versões incluídas na imagem (Debian, Arrow, Oracle Instant Client, numpy) não entram na tag.
- Nenhuma tag é publicada se o build tiver vulnerabilidade **crítica com correção disponível** (verificação no CI com o Grype). Os CVEs que não se aplicam a esta imagem, por exemplo de drivers do GDAL que não são compilados, estão declarados em [vex/gdal-oci.openvex.json](vex/gdal-oci.openvex.json) (OpenVEX).
- **Tag legada:** a `3.4.3` é de 2023 e não foi gerada por este Dockerfile. Ela é mantida só para compatibilidade, **sem manutenção**: não é refeita, não recebe correções de segurança e não tem SBOM. Não use em projetos novos; migre para uma tag `<gdal>-py<python>`.

## O que vem incluído

Tudo fica em `/opt/geosgb`:

| Caminho | Conteúdo |
|---|---|
| `/opt/geosgb/bin` | Utilitários do GDAL (`gdalinfo`, `ogr2ogr`, `gdal_translate`, …) |
| `/opt/geosgb/lib` | `libgdal.so` e as bibliotecas do Apache Arrow/Parquet (`libarrow*.so`, `libparquet.so`) |
| `/opt/geosgb/share/gdal` | Dados do GDAL (`GDAL_DATA`) |
| `/opt/geosgb/venv` | Virtualenv Python com os bindings `osgeo` e numpy |
| `/opt/geosgb/oracle` | Oracle Instant Client 19.32 (basiclite; o SDK fica só no `devel`) |
| `/opt/geosgb/include`, `lib/cmake`, `lib/pkgconfig`, `src` | Só no `devel` |

**Drivers.** A imagem não vem com todos os drivers do GDAL, só com estes:

| Categoria | Drivers |
|---|---|
| Bancos de dados | Oracle Spatial (`OCI`), PostGIS vetor (`PostgreSQL`, `PGDUMP`) e raster (`PostGISRaster`), `SQLite`, `Elasticsearch` |
| Arquivos vetoriais | `GPKG`, `OpenFileGDB`, `Parquet`, `Arrow`, `KML`, `LIBKML` (KML/KMZ), `GML`, `MVT`, `GeoJSON`, `ESRI Shapefile` |
| Arquivos raster | `GTiff`, `COG`, `GPKG`, `PNG`, `JPEG`, `VRT` |
| Serviços OGC | `WMS`, `WFS`, `WCS`, `OGCAPI` (Tiles/Maps/Coverages), `OAPIF` (OGC API Features) |
| Acesso remoto | `/vsicurl/` (HTTP/HTTPS) |

Para conferir dentro do container:

```bash
docker run --rm docker.io/ndscprm/gdal:3.12.4-py3.12 ogrinfo --formats
docker run --rm docker.io/ndscprm/gdal:3.12.4-py3.12 gdalinfo --formats
```

Para incluir outro driver, ele precisa ser ligado no `cmake` do Dockerfile (veja [CLAUDE.md](CLAUDE.md)).

## Build

```bash
IMAGE=docker.io/ndscprm/gdal
GDAL_VERSION=3.12.4
PYTHON_VERSION=3.12
TAG=${GDAL_VERSION}-py${PYTHON_VERSION}

# devel primeiro; o release reaproveita o cache dele, então as duas saem do mesmo build
docker build --target devel \
  --build-arg GDAL_VERSION=${GDAL_VERSION} --build-arg PYTHON_VERSION=${PYTHON_VERSION} \
  -t ${IMAGE}:${TAG}-devel .
docker build \
  --build-arg GDAL_VERSION=${GDAL_VERSION} --build-arg PYTHON_VERSION=${PYTHON_VERSION} \
  -t ${IMAGE}:${TAG} .

docker push ${IMAGE}:${TAG}-devel
docker push ${IMAGE}:${TAG}
```

Ao mudar o `GDAL_VERSION`, passe também o `GDAL_SHA256` correspondente (veja [Versões e build args](#versões-e-build-args)). Os valores padrão do Dockerfile correspondem ao GDAL 3.12.4 com Python 3.12.

O build compila o Apache Arrow e o GDAL e leva de 15 a 25 minutos, conforme o número de núcleos da máquina. As arquiteturas suportadas são `linux/amd64` e `linux/arm64` (o Oracle Instant Client tem as duas), e o CI faz o build e o smoke test de ambas.

Os comandos acima servem para testes locais. As imagens publicadas devem sair do [CI](.github/workflows/docker-image.yml): um `docker push` manual gera uma imagem sem attestations de SBOM e provenance, que não passou pelo smoke test nem pela verificação de vulnerabilidades e não tem tag datada.

## Usando o `release` como base

### Ambiente Python

O virtualenv `/opt/geosgb/venv` vem **ativo por padrão**: `python`, `python3` e `pip` resolvem para ele pelo `PATH`, sem precisar de `activate`. Instale as dependências da aplicação nesse mesmo venv:

```dockerfile
FROM docker.io/ndscprm/gdal:3.12.4-py3.12

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
CMD ["python", "app.py"]
```

```python
from osgeo import gdal, ogr, osr, gdal_array
gdal.UseExceptions()
```

Regras:

- **Não instale o pacote `GDAL` do PyPI** (`pip install gdal`). Ele substituiria os bindings da imagem, que foram compilados com os drivers acima.
- **numpy:** os bindings foram compilados com numpy 2.x e funcionam com qualquer numpy **a partir da 1.25**. Pode fazer upgrade ou downgrade do numpy livremente dentro dessa faixa.
- **Bibliotecas Python que dependem do GDAL** (ex.: `fiona`, `rasterio`): as wheels do PyPI trazem uma cópia própria do GDAL, com versão e drivers diferentes dos desta imagem, e assim ficam duas cópias do GDAL no container. Para que elas usem o GDAL da imagem, compile a partir do código-fonte no `devel` (veja [examples/fiona](examples/fiona/)). Essas bibliotecas também podem ter uma lista própria de drivers liberados, que não inclui todos os do GDAL.

### Exemplos

O diretório [examples/](examples/) tem imagens derivadas completas, cada uma com Dockerfile e README:

| Exemplo | Base | O que mostra |
|---|---|---|
| [examples/fiona](examples/fiona/) | `devel` → `release` | `fiona` compilado contra o GDAL da imagem, estendendo o venv no `devel` |
| [examples/django](examples/django/) | `release` | GeoDjango + PostGIS (Compose): modelo com `PointField`, consulta por distância, admin com mapa, importação de qualquer formato do GDAL e migrations via `/docker-entrypoint.d` |

### Scripts de inicialização (`/docker-entrypoint.d`)

O entrypoint (igual no `release` e no `devel`) executa os scripts `*.sh` de `/docker-entrypoint.d`, em ordem alfabética, antes do comando do container. A convenção é a mesma da imagem oficial do PostgreSQL:

| Permissão do arquivo | O que acontece | Use para |
|---|---|---|
| Com `+x` (ex.: `755`) | **Executado** em outro processo | Ações: esperar um serviço, criar diretórios, baixar arquivos |
| Sem `+x` (ex.: `644`) | **Carregado** (`source`) no próprio entrypoint, e as variáveis exportadas chegam ao comando | Definir variáveis de ambiente na subida do container |

Arquivos que não terminam em `.sh` são ignorados.

```dockerfile
FROM docker.io/ndscprm/gdal:3.12.4-py3.12
COPY --chmod=755 10-wait-db.sh  /docker-entrypoint.d/
COPY --chmod=644 20-env.sh      /docker-entrypoint.d/
```

```sh
# 20-env.sh (carregado: só exports)
export DATABASE_URL="postgresql://${DB_USER}:$(cat /run/secrets/db_password)@${DB_HOST}/gis"
```

Cuidados:

- **Sempre defina a permissão com `COPY --chmod`.** A permissão decide se o script é executado ou carregado, e ela pode se perder no caminho até a imagem (clone no Windows, `core.fileMode=false`, ConfigMaps do Kubernetes montados com `0644`).
- **Não use `exit` em scripts sem `+x`**, nem `exit 0`. Como eles rodam dentro do entrypoint, o `exit` encerra o container antes de o comando rodar. Também evite `cd`, `set +e` e funções nesses scripts, porque tudo isso continua valendo para os scripts seguintes.
- **Mande os logs para o stderr** (`echo "..." >&2`). O stdout é a saída do comando do container. Uma mensagem ali corrompe, por exemplo, um `ogr2ogr -f GeoJSON /vsistdout/ ... > saida.json`.
- Um script que falha (código de saída diferente de zero) impede o container de subir.
- Com `ENTRYPOINT_QUIET_LOGS=1`, o entrypoint não registra quais scripts executou.

Imagens derivadas que definem só `CMD` continuam passando pelo entrypoint. Se a imagem derivada definir `ENTRYPOINT`, os scripts de `/docker-entrypoint.d` deixam de rodar. Para manter os scripts, encadeie o entrypoint original:

```dockerfile
ENTRYPOINT ["/docker-entrypoint.sh", "meu-entrypoint.sh"]
```

### Rodando com UID arbitrário (OpenShift, `--user`)

As duas imagens já incluem o script [`10-enable-nss-wrapper.sh`](docker-entrypoint.d/10-enable-nss-wrapper.sh). Quando o container roda com um UID que não existe no `/etc/passwd` (como no OpenShift ou com `docker run --user 12345:0`), ele usa o `nss_wrapper` para:

- criar um usuário virtual com o nome de `USER_NAME` (padrão `sgb`), para que `whoami`, `getpass.getuser()` e bibliotecas que consultam o passwd funcionem. O nome deve começar por letra ou `_` e ter só letras, dígitos, `.`, `_` ou `-` (até 32 caracteres). Um valor inválido impede o container de iniciar;
- definir `HOME=/tmp` quando o `HOME` herdado for `/` ou não for gravável.

Rodando como root ou com um usuário que já existe na imagem, o script não faz nada. Se a imagem derivada criar o próprio usuário (`useradd` + `USER`), o nss_wrapper também não entra em ação.

### Variáveis de ambiente

| Variável | Valor padrão | Descrição |
|---|---|---|
| `GDAL_DATA` | `/opt/geosgb/share/gdal` | Dados do GDAL |
| `VIRTUAL_ENV` | `/opt/geosgb/venv` | Venv ativo |
| `PATH` | `/opt/geosgb/venv/bin:/opt/geosgb/bin:…` | Venv e utilitários do GDAL primeiro |
| `ENTRYPOINT_QUIET_LOGS` | (vazia) | Qualquer valor silencia os logs do entrypoint |
| `USER_NAME` | `sgb` | Nome do usuário virtual criado pelo nss_wrapper (letras, dígitos, `.`, `_` ou `-`; começando por letra ou `_`) |

As opções de configuração do GDAL (`GDAL_HTTP_*`, `CPL_*`, `OGR_*` etc.) funcionam normalmente como variáveis de ambiente.

### Abrindo arquivos enviados por usuários

Esta seção vale para aplicações que abrem com o GDAL arquivos ou caminhos vindos de fora (upload, parâmetro de API, URL informada pelo usuário). Para o GDAL, **abrir um arquivo já é processá-lo**. Esta imagem habilita drivers que acessam a rede (WMS, WCS, WFS, OAPIF, OGCAPI, Elasticsearch, `/vsicurl/`) e drivers que abrem outros datasets por dentro (VRT e os de serviços OGC). Por isso, um "arquivo" malicioso pode fazer o servidor acessar URLs internas (SSRF). Exemplos testados nesta imagem: um `.vrt` cuja fonte é `/vsicurl/http://<host interno>/...` e um `.xml` do driver WMS apontando para um endereço interno. Nos dois casos o GDAL faz a requisição assim que o arquivo é aberto.

Recomendações, da mais importante para a menos:

1. **Restrinja os drivers na abertura.** Liste só os formatos que a aplicação aceita. Um arquivo de outro formato (VRT, XML do WMS etc.) é recusado:

   ```python
   from osgeo import gdal
   gdal.UseExceptions()
   ds = gdal.OpenEx(caminho, gdal.OF_VECTOR, allowed_drivers=["GPKG", "GeoJSON", "Parquet"])
   ```

2. **Desligue globalmente os drivers que a aplicação não usa** com `GDAL_SKIP` (nomes curtos separados por espaço, valendo para drivers raster e vetoriais). Por exemplo, numa aplicação que só lê arquivos locais:

   ```dockerfile
   ENV GDAL_SKIP="VRT WMS WCS WFS OAPIF OGCAPI Elasticsearch"
   ```

3. **Nunca repasse ao GDAL uma string do usuário como caminho.** Grave o upload com um nome gerado pela aplicação, num diretório próprio, e abra esse caminho. Isso evita prefixos como `/vsicurl/`, `/vsizip/` e `/vsis3/` e strings de conexão como `PG:`, `OCI:`, `WFS:` e `ES:`. Pelo mesmo motivo, não aceite do usuário opções de utilitários (`gdal.Translate`/`gdal.VectorTranslate`, `-sql`, `-where`), opções de configuração (`--config`, `gdal.SetConfigOption`) nem expressões do `gdal_calc` (avaliadas com `eval()`).
4. **Restrinja a saída de rede do container** (NetworkPolicy no Kubernetes/OpenShift, regras de firewall) ao que a aplicação realmente acessa, em especial a rede interna e o endereço de metadados da nuvem (`169.254.169.254`). Isso limita o estrago se algo passar pelas camadas anteriores.
5. **Limite os recursos.** Arquivos pequenos podem declarar dimensões enormes ou descompactar para gigabytes. Confira `RasterXSize`, `RasterYSize` e `RasterCount` antes de ler os dados. Rode com limites de memória e CPU no container e com timeout no processamento.
6. **Isole o processo.** Rode como usuário sem privilégios (a imagem já suporta UID arbitrário). Se possível, use sistema de arquivos somente leitura (`--read-only` com `/tmp` gravável). Senhas de conexões (Oracle, PostGIS) ficam na memória do processo que abre os arquivos.

Mais detalhes: [Security considerations](https://gdal.org/en/stable/user/security.html), na documentação do GDAL.

## Usando o `devel` como base

### Compilando código contra o GDAL

O `devel` traz os headers e os arquivos de configuração para os três mecanismos usuais:

```bash
# gdal-config (já está no PATH)
gcc app.c $(gdal-config --cflags) $(gdal-config --libs) -o app

# CMake
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/geosgb   # find_package(GDAL CONFIG REQUIRED) + GDAL::GDAL

# pkg-config (o .pc não fica no caminho padrão)
PKG_CONFIG_PATH=/opt/geosgb/lib/pkgconfig pkg-config --cflags --libs gdal
```

### Padrão recomendado: compilar no `devel`, rodar no `release`

Compile no `devel` e copie só o resultado para uma imagem baseada no `release`. Como os dois usam os mesmos caminhos e o mesmo GDAL, o binário roda sem ajustes. O exemplo abaixo foi testado:

```dockerfile
FROM docker.io/ndscprm/gdal:3.12.4-py3.12-devel AS build
COPY . /src
RUN cmake -S /src -B /src/build -DCMAKE_PREFIX_PATH=/opt/geosgb && \
    cmake --build /src/build

FROM docker.io/ndscprm/gdal:3.12.4-py3.12
COPY --from=build /src/build/app /usr/local/bin/
CMD ["app"]
```

Se o código compilado depender de **outras bibliotecas de sistema** além do GDAL, instale no `release` derivado os pacotes de runtime correspondentes (sem `-dev`).

**Use o `devel` e o `release` da mesma versão** (ex.: `docker.io/ndscprm/gdal:3.12.4-py3.12-devel` com `docker.io/ndscprm/gdal:3.12.4-py3.12`). Os artefatos compilados num build e copiados para a imagem de outro build podem não bater com o GDAL e o numpy dela.

### Estendendo o virtualenv no `devel`

Pacotes Python com extensões nativas que precisam compilar contra o GDAL da imagem (`fiona`, `rasterio` com `--no-binary`) são instalados no venv `/opt/geosgb/venv` do `devel`, e o venv inteiro é copiado para o `release`:

```dockerfile
FROM docker.io/ndscprm/gdal:3.12.4-py3.12-devel AS build
RUN pip install --no-cache-dir --no-binary fiona "fiona==1.10.1"

FROM docker.io/ndscprm/gdal:3.12.4-py3.12
COPY --from=build /opt/geosgb/venv /opt/geosgb/venv
```

O exemplo completo, com verificação no build e os cuidados (o `COPY` substitui o venv inteiro; fixar versões), está em [examples/fiona](examples/fiona/).

### Depuração com gdb

O `devel` tem `gdb`, os símbolos de debug do GDAL e o código-fonte em `/opt/geosgb/src/gdal-3.12.4`. O gdb mostra o código-fonte nos backtraces sem precisar de configuração. O container precisa da permissão de ptrace:

```bash
docker run --rm -it --cap-add=SYS_PTRACE --security-opt seccomp=unconfined docker.io/ndscprm/gdal:3.12.4-py3.12-devel bash

gdb --args gdalinfo arquivo.tif
(gdb) break GDALOpenEx
(gdb) run
(gdb) bt
```

Para analisar um core dump gerado no `release`, abra-o no `devel` da mesma versão: os binários são os mesmos, só que com os símbolos.

## Versões e build args

| Arg | Padrão |
|---|---|
| `PYTHON_VERSION` | `3.12` |
| `DEBIAN_VERSION` | `trixie` |
| `GDAL_VERSION` / `GDAL_SHA256` | `3.12.4` / SHA256 do tarball |
| `ARROW_VERSION` / `ARROW_SHA256` | `26.0.0` / SHA256 do tarball |
| `THRIFT_VERSION` / `THRIFT_SHA256` | `0.25.0` / SHA256 do tarball |
| `HARDENING_CFLAGS` / `HARDENING_LDFLAGS` | stack protector, `_FORTIFY_SOURCE=3`, stack clash protection e RELRO completo (GDAL, Arrow e Thrift) |
| numpy | `2.5.4` (versão usada para compilar os bindings; fixada com hash em [requirements/venv.txt](requirements/venv.txt), junto com pip, setuptools e wheel) |
| Oracle Instant Client | `19.32.0.0.0` |

Todos os downloads são verificados contra valores fixados no repositório: o SHA256 do GDAL, do Arrow, do Thrift e do Oracle no Dockerfile, e os hashes dos pacotes Python do venv em [requirements/venv.txt](requirements/venv.txt) (`pip install --require-hashes`). Para mudar a versão de um deles, é preciso atualizar também o hash correspondente. O procedimento está no [CLAUDE.md](CLAUDE.md). As imagens base `python` são referenciadas por tag, para que o rebuild semanal pegue as correções delas. O digest exato usado em cada build fica registrado no provenance.

O Apache Arrow/Parquet é compilado do código-fonte, e não instalado do repositório apt do Arrow, para que o Parquet use uma versão do Apache Thrift com as correções de segurança em dia. O Thrift do Debian trixie (0.19) tem CVEs abertos e sem previsão de correção. O Thrift fica embutido no `libparquet.so` (link estático), então não aparece como pacote na imagem.

**SBOM.** As imagens publicadas têm attestations de SBOM (SPDX) e de provenance. Para ver: `docker buildx imagetools inspect docker.io/ndscprm/gdal:3.12.4-py3.12 --format '{{ json .SBOM }}'`. Os componentes que não vêm do apt (GDAL, Arrow, Thrift, xsimd, simdjson, Oracle Instant Client) também ficam descritos em CycloneDX em `/opt/geosgb/share/sbom/`, dentro da imagem. Para analisar a imagem com o Grype, use a attestation (`grype sbom:<arquivo SPDX>`). Analisando a imagem direto, o Grype não lê esses arquivos. Outra opção é gerar o SBOM com `syft <imagem> --select-catalogers +sbom-cataloger -o spdx-json` e passá-lo ao Grype.

## Licença

[Apache License 2.0](LICENSE). Os componentes incluídos na imagem têm licenças próprias, em especial o **Oracle Instant Client**, distribuído sob a licença da Oracle.
