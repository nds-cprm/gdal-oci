# docker.io/ndscprm/gdal

> Documentação gerada por IA (Claude) e revisada por humanos 

Imagens Docker base com **GDAL 3.12.4 compilado do código-fonte**, bindings Python, Apache Arrow/Parquet (com **pyarrow** compilado contra as mesmas bibliotecas) e **Oracle Instant Client**, para servir de base a imagens de aplicações Python geoespaciais.

O mesmo [Dockerfile](Dockerfile) gera três imagens:

| | `devel` | `release-py` | `release-nopy` |
|---|---|---|---|
| **Para quê** | Compilar código contra o GDAL e depurar | Base de imagens de aplicação (produção) | Utilitários do GDAL e aplicações C/C++, sem Python |
| **Base** | `python:3.12-trixie` | `python:3.12-slim-trixie` | `debian:trixie-slim` |
| **Tamanho** | ~2,4 GB | ~620 MB | ~450 MB |
| **GDAL** | Binários com símbolos de debug, headers, CMake/pkg-config e código-fonte em `/opt/geosgb/src` | Binários e bibliotecas, sem símbolos de debug | Igual ao `release-py` |
| **Python** | Virtualenv com os bindings `osgeo`, numpy e pyarrow | Igual ao `devel` | Não tem (nem os utilitários em Python, como `gdal_calc.py`) |
| **Ferramentas** | `build-essential`, `cmake`, `swig`, `gdb` e os pacotes `-dev` de todas as dependências | Só o runtime | Só o runtime |
| **Entrypoint** | [`/docker-entrypoint.sh`](docker-entrypoint.sh) + `/docker-entrypoint.d` | Igual ao `devel` | Igual ao `devel` |
| **CMD** | `python3` | `python3` | `bash` |

As três imagens têm o mesmo GDAL compilado uma única vez (`-O3`). O `release-py` é o `devel` sem os símbolos de debug, sem os arquivos usados só no build e com apenas as bibliotecas de runtime que o GDAL realmente usa (detectadas com `ldd` durante o build). O `release-nopy` é o `release-py` sem o Python e sem o virtualenv.

## Imagens e tags

As imagens são publicadas em `docker.io/ndscprm/gdal`. A tag é formada pela **versão do GDAL** e pela **versão do Python**:

| Imagem | Tag | Exemplo |
|---|---|---|
| `release-py` | `<gdal>-py<python>` | `docker.io/ndscprm/gdal:3.12.4-py3.12` |
| `devel` | `<gdal>-py<python>-devel` | `docker.io/ndscprm/gdal:3.12.4-py3.12-devel` |
| `release-py` (build específico) | `<gdal>-py<python>-<AAAAMMDD>` | `docker.io/ndscprm/gdal:3.12.4-py3.12-20261026` |
| `devel` (build específico) | `<gdal>-py<python>-devel-<AAAAMMDD>` | `docker.io/ndscprm/gdal:3.12.4-py3.12-devel-20261026` |
| `release-nopy` | `<gdal>-nopy` | `docker.io/ndscprm/gdal:3.12.4-nopy` |
| `release-nopy` (build específico) | `<gdal>-nopy-<AAAAMMDD>` | `docker.io/ndscprm/gdal:3.12.4-nopy-20261026` |

- `<gdal>` é a versão completa do GDAL (`GDAL_VERSION`, ex.: `3.12.4`), e `<python>` é a versão `major.minor` do Python (`PYTHON_VERSION`, ex.: `3.12`). A tag do `release-nopy` não tem `<python>`, porque a imagem não tem Python.
- As tags de uma mesma versão (`release-py`, `devel` e `release-nopy`) são **sempre geradas e publicadas juntas, a partir do mesmo build**. Elas são feitas para serem usadas em conjunto (veja [Padrão recomendado](#padrão-recomendado-compilar-no-devel-rodar-no-release-py)).
- As imagens são **refeitas toda semana** para incorporar as correções de segurança do Debian e do Python. As tags `<gdal>-py<python>[-devel]` e `<gdal>-nopy` são móveis e sempre apontam para o build mais recente. As tags com data (`-<AAAAMMDD>`, em UTC) identificam um build e nunca são sobrescritas; um segundo build no mesmo dia recebe `.2`, `.3`, ... Para fixar exatamente um build, use a tag com data ou o digest (`docker.io/ndscprm/gdal:3.12.4-py3.12@sha256:…`).
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
| `/opt/geosgb/venv` | Virtualenv Python com os bindings `osgeo`, numpy e pyarrow (não existe no `release-nopy`) |
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

# devel primeiro; o release-py e o release-nopy reaproveitam o cache dele, então as três saem do mesmo build
docker build --target devel \
  --build-arg GDAL_VERSION=${GDAL_VERSION} --build-arg PYTHON_VERSION=${PYTHON_VERSION} \
  -t ${IMAGE}:${TAG}-devel .
docker build \
  --build-arg GDAL_VERSION=${GDAL_VERSION} --build-arg PYTHON_VERSION=${PYTHON_VERSION} \
  -t ${IMAGE}:${TAG} .
docker build --target release-nopy \
  --build-arg GDAL_VERSION=${GDAL_VERSION} --build-arg PYTHON_VERSION=${PYTHON_VERSION} \
  -t ${IMAGE}:${GDAL_VERSION}-nopy .

docker push ${IMAGE}:${TAG}-devel
docker push ${IMAGE}:${TAG}
docker push ${IMAGE}:${GDAL_VERSION}-nopy
```

Ao mudar o `GDAL_VERSION`, passe também o `GDAL_SHA256` correspondente (veja [Versões e build args](#versões-e-build-args)). Os valores padrão do Dockerfile correspondem ao GDAL 3.12.4 com Python 3.12.

O build compila o Apache Arrow e o GDAL e leva de 15 a 25 minutos, conforme o número de núcleos da máquina. As arquiteturas suportadas são `linux/amd64` e `linux/arm64` (o Oracle Instant Client tem as duas), e o CI faz o build e o smoke test de ambas.

Os comandos acima servem para testes locais. As imagens publicadas devem sair do [CI](.github/workflows/docker-image.yml): um `docker push` manual gera uma imagem sem attestations de SBOM e provenance, que não passou pelo smoke test nem pela verificação de vulnerabilidades e não tem tag datada.

## Usando o `release-py` como base

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
- **pyarrow:** o venv já vem com o pyarrow 26.0.0, compilado contra o mesmo Arrow C++ que o GDAL usa (`/opt/geosgb/lib`). **Não instale o `pyarrow` do PyPI**: a wheel traz um Arrow C++ próprio, e o container ficaria com duas cópias do Arrow. Um pacote que dependa do pyarrow mantém o da imagem quando a versão exigida é compatível. Se ele exigir outra versão (ex.: `pyarrow<26`), o pip troca o pyarrow da imagem pela wheel do PyPI sem avisar. Para o pip falhar nesse caso, em vez de trocar, use um arquivo de constraints (veja o exemplo abaixo).
- **Bibliotecas Python que dependem do GDAL** (ex.: `fiona`, `rasterio`): as wheels do PyPI trazem uma cópia própria do GDAL, com versão e drivers diferentes dos desta imagem, e assim ficam duas cópias do GDAL no container. Para que elas usem o GDAL da imagem, compile a partir do código-fonte no `devel` (veja [examples/fiona](examples/fiona/)). Essas bibliotecas também podem ter uma lista própria de drivers liberados, que não inclui todos os do GDAL.

### pyarrow

O GDAL e o pyarrow usam as mesmas bibliotecas do Arrow, então os dados passam de um para o outro pela interface C do Arrow (ArrowStream), sem conversão por feição:

```python
import pyarrow as pa
import pyarrow.parquet as pq
from osgeo import ogr
ogr.UseExceptions()

ds = ogr.Open("dados.gpkg")
# o Layer implementa a PyCapsule interface do Arrow (__arrow_c_stream__)
table = pa.table(ds.GetLayer(0))
pq.write_table(table, "dados.parquet", compression="zstd")
```

Para instalar dependências sem deixar o pip trocar o pyarrow da imagem:

```dockerfile
RUN echo "pyarrow==26.0.0" > /tmp/constraints.txt && \
    pip install --no-cache-dir -c /tmp/constraints.txt -r requirements.txt
```

Com a constraint, um pacote que exija outra versão do pyarrow faz o `pip install` falhar no build, em vez de instalar a wheel do PyPI.

### Exemplos

O diretório [examples/](examples/) tem imagens derivadas completas, cada uma com Dockerfile e README:

| Exemplo | Base | O que mostra |
|---|---|---|
| [examples/fiona](examples/fiona/) | `devel` → `release-py` | `fiona` compilado contra o GDAL da imagem, estendendo o venv no `devel` |
| [examples/django](examples/django/) | `release-py` | GeoDjango + PostGIS (Compose): modelo com `PointField`, consulta por distância, admin com mapa, importação de qualquer formato do GDAL e migrations via `/docker-entrypoint.d` |

### Scripts de inicialização (`/docker-entrypoint.d`)

O entrypoint (igual no `release-py` e no `devel`) executa os scripts `*.sh` de `/docker-entrypoint.d`, em ordem alfabética, antes do comando do container. A convenção é a mesma da imagem oficial do PostgreSQL:

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

As três imagens já incluem o script [`10-enable-nss-wrapper.sh`](docker-entrypoint.d/10-enable-nss-wrapper.sh). Quando o container roda com um UID que não existe no `/etc/passwd` (como no OpenShift ou com `docker run --user 12345:0`), ele usa o `nss_wrapper` para:

- criar um usuário virtual com o nome de `USER_NAME` (padrão `sgb`), para que `whoami`, `getpass.getuser()` e bibliotecas que consultam o passwd funcionem. O nome deve começar por letra ou `_` e ter só letras, dígitos, `.`, `_` ou `-` (até 32 caracteres). Um valor inválido impede o container de iniciar;
- definir `HOME=/tmp` quando o `HOME` herdado estiver vazio ou for `/` (o Docker usa `/` para UID sem passwd). Qualquer outro `HOME` é mantido, mesmo sem permissão de escrita: imagens derivadas usam o `HOME` como diretório de configuração, e com `--read-only` ele não é gravável.

Rodando como root ou com um usuário que já existe na imagem, o script não faz nada. Se a imagem derivada criar o próprio usuário (`useradd` + `USER`), o nss_wrapper também não entra em ação.

**Sistema de arquivos somente leitura.** As imagens funcionam com `--read-only` (no Kubernetes/OpenShift, `readOnlyRootFilesystem: true`). Com UID arbitrário, porém, o nss_wrapper grava o `passwd` e o `group` virtuais num diretório temporário. Por isso o container precisa de um `/tmp` gravável; sem ele, não inicia e informa o motivo no stderr. Use um `/tmp` em memória:

```bash
# volume para o HOME, gravável pelo grupo 0 (o UID arbitrário roda com GID 0)
docker volume create dados-app
docker run --rm -v dados-app:/v docker.io/ndscprm/gdal:3.12.4-py3.12 chmod 0775 /v

docker run --read-only --tmpfs /tmp --user 12345:0 \
  -e HOME=/home/app -v dados-app:/home/app \
  docker.io/ndscprm/gdal:3.12.4-py3.12 python app.py
```

```yaml
# Kubernetes/OpenShift (trecho do pod)
securityContext:
  readOnlyRootFilesystem: true
volumeMounts:
  - name: tmp
    mountPath: /tmp
volumes:
  - name: tmp
    emptyDir:
      medium: Memory
```

- `TMPDIR` também é aceito (o diretório temporário vira `$TMPDIR`). Não aponte para um volume persistente, porque cada start deixa ali um diretório `nss_wrapper.*`.
- Um volume montado no `HOME` precisa ser gravável pelo UID do container. Se não for, o script não percebe e mantém o `HOME`, e o erro só aparece quando a aplicação tentar gravar ali. Um volume nomeado novo do Docker nasce sem escrita para outros UIDs: no primeiro uso, ele copia a permissão do diretório que existe na imagem naquele caminho (`/root` é 0700). Se o caminho não existir na imagem, como `/home/app`, o volume é criado como `root` com 0755. Por isso o exemplo acima faz o `chmod 0775` antes. No Kubernetes/OpenShift, use `fsGroup` no `securityContext` do pod (a SCC padrão do OpenShift já atribui um).
- Rodando como root, não há essa exigência: o nss_wrapper não entra em ação.

### Variáveis de ambiente

| Variável | Valor padrão | Descrição |
|---|---|---|
| `GDAL_DATA` | `/opt/geosgb/share/gdal` | Dados do GDAL |
| `VIRTUAL_ENV` | `/opt/geosgb/venv` | Venv ativo (não definida no `release-nopy`) |
| `PATH` | `/opt/geosgb/venv/bin:/opt/geosgb/bin:…` | Venv e utilitários do GDAL primeiro (no `release-nopy`, `/opt/geosgb/bin:…`) |
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

## Usando o `release-nopy` como base

O `release-nopy` é o `release-py` sem Python, para quem só usa os utilitários do GDAL (`gdalinfo`, `ogr2ogr`, `gdal_translate`, `gdalwarp`, a CLI `gdal` etc.) ou a API C/C++. Tem os mesmos drivers, o mesmo entrypoint, o suporte a UID arbitrário (nss_wrapper) e as mesmas recomendações de [Abrindo arquivos enviados por usuários](#abrindo-arquivos-enviados-por-usuários).

```bash
docker run --rm -v "$PWD:/data" -w /data docker.io/ndscprm/gdal:3.12.4-nopy \
  ogr2ogr -f Parquet saida.parquet entrada.gpkg
```

O que **não** existe no `release-nopy`:

- Python, o virtualenv `/opt/geosgb/venv`, os bindings `osgeo` e o numpy. A variável `VIRTUAL_ENV` não é definida, e o `PATH` tem só `/opt/geosgb/bin`.
- Os utilitários do GDAL escritos em Python, que ficam no venv: `gdal_calc.py`, `gdal2tiles.py`, `gdal_merge.py`, `ogrmerge.py`, `gdal_polygonize.py`, `gdal_edit.py` e os demais `*.py`. Muitos têm equivalente na CLI `gdal` (ex.: `gdal raster calc`, `gdal raster tile`, `gdal vector concat`).

Scripts em `/docker-entrypoint.d` funcionam do mesmo jeito, mas precisam ser em `sh`/`bash`.

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

### Padrão recomendado: compilar no `devel`, rodar no `release-py`

Compile no `devel` e copie só o resultado para uma imagem baseada no `release-py`. Como os dois usam os mesmos caminhos e o mesmo GDAL, o binário roda sem ajustes. O exemplo abaixo foi testado:

```dockerfile
FROM docker.io/ndscprm/gdal:3.12.4-py3.12-devel AS build
COPY . /src
RUN cmake -S /src -B /src/build -DCMAKE_PREFIX_PATH=/opt/geosgb && \
    cmake --build /src/build

FROM docker.io/ndscprm/gdal:3.12.4-py3.12
COPY --from=build /src/build/app /usr/local/bin/
CMD ["app"]
```

Se o código compilado depender de **outras bibliotecas de sistema** além do GDAL, instale no `release-py` derivado os pacotes de runtime correspondentes (sem `-dev`).

**Use o `devel` e o `release-py` da mesma versão** (ex.: `docker.io/ndscprm/gdal:3.12.4-py3.12-devel` com `docker.io/ndscprm/gdal:3.12.4-py3.12`). Os artefatos compilados num build e copiados para a imagem de outro build podem não bater com o GDAL e o numpy dela.

### Estendendo o virtualenv no `devel`

Pacotes Python com extensões nativas que precisam compilar contra o GDAL da imagem (`fiona`, `rasterio` com `--no-binary`) são instalados no venv `/opt/geosgb/venv` do `devel`, e o venv inteiro é copiado para o `release-py`:

```dockerfile
FROM docker.io/ndscprm/gdal:3.12.4-py3.12-devel AS build
RUN pip install --no-cache-dir --no-binary fiona "fiona==1.10.1"

FROM docker.io/ndscprm/gdal:3.12.4-py3.12
COPY --from=build /opt/geosgb/venv /opt/geosgb/venv
```

O exemplo completo, com verificação no build e os cuidados (o `COPY` substitui o venv inteiro; fixar versões), está em [examples/fiona](examples/fiona/).

### Rodando no `release-nopy`

Um binário compilado no `devel` que não usa Python também roda no `release-nopy`, que tem o mesmo GDAL nos mesmos caminhos e é menor que o `release-py`:

```dockerfile
FROM docker.io/ndscprm/gdal:3.12.4-py3.12-devel AS build
COPY . /src
RUN cmake -S /src -B /src/build -DCMAKE_PREFIX_PATH=/opt/geosgb && \
    cmake --build /src/build

FROM docker.io/ndscprm/gdal:3.12.4-nopy
COPY --from=build /src/build/app /usr/local/bin/
CMD ["app"]
```

Use o `devel` e o `release-nopy` do mesmo build (a tag datada de um corresponde à do outro, ex.: `3.12.4-py3.12-devel-20261026` e `3.12.4-nopy-20261026`).

### Depuração com gdb

O `devel` tem `gdb`, os símbolos de debug do GDAL e o código-fonte em `/opt/geosgb/src/gdal-3.12.4`. O gdb mostra o código-fonte nos backtraces sem precisar de configuração. O container precisa da permissão de ptrace:

```bash
docker run --rm -it --cap-add=SYS_PTRACE --security-opt seccomp=unconfined docker.io/ndscprm/gdal:3.12.4-py3.12-devel bash

gdb --args gdalinfo arquivo.tif
(gdb) break GDALOpenEx
(gdb) run
(gdb) bt
```

Para analisar um core dump gerado no `release-py`, abra-o no `devel` da mesma versão: os binários são os mesmos, só que com os símbolos.

## Versões e build args

| Arg | Padrão |
|---|---|
| `PYTHON_VERSION` | `3.12` |
| `DEBIAN_VERSION` | `trixie` |
| `GDAL_VERSION` / `GDAL_SHA256` | `3.12.4` / SHA256 do tarball |
| `ARROW_VERSION` / `ARROW_SHA256` | `26.0.0` / SHA256 do tarball |
| `THRIFT_VERSION` / `THRIFT_SHA256` | `0.25.0` / SHA256 do tarball |
| `HARDENING_CFLAGS` / `HARDENING_LDFLAGS` | stack protector, `_FORTIFY_SOURCE=3`, stack clash protection e RELRO completo (GDAL, Arrow, Thrift e pyarrow) |
| numpy | `2.5.4` (versão usada para compilar os bindings; fixada com hash em [requirements/gdal-build.txt](requirements/gdal-build.txt), junto com pip, setuptools e wheel) |
| pyarrow | igual ao `ARROW_VERSION` (`26.0.0`), compilado do mesmo tarball do Arrow; as dependências de build ficam fixadas com hash em [requirements/pyarrow-build.txt](requirements/pyarrow-build.txt) e não entram na imagem |
| Oracle Instant Client | `19.32.0.0.0` |

Todos os downloads são verificados contra valores fixados no repositório: o SHA256 do GDAL, do Arrow, do Thrift e do Oracle no Dockerfile, e os hashes dos pacotes Python do venv e do build do pyarrow em [requirements/gdal-build.txt](requirements/gdal-build.txt) e [requirements/pyarrow-build.txt](requirements/pyarrow-build.txt) (`pip install --require-hashes`). Para mudar a versão de um deles, é preciso atualizar também o hash correspondente. O procedimento está no [CLAUDE.md](CLAUDE.md). As imagens base (`python` e, no `release-nopy`, `debian`) são referenciadas por tag, para que o rebuild semanal pegue as correções delas. O digest exato usado em cada build fica registrado no provenance.

O Apache Arrow/Parquet é compilado do código-fonte, e não instalado do repositório apt do Arrow, para que o Parquet use uma versão do Apache Thrift com as correções de segurança em dia. O Thrift do Debian trixie (0.19) tem CVEs abertos e sem previsão de correção. O Thrift fica embutido no `libparquet.so` (link estático), então não aparece como pacote na imagem. O pyarrow é compilado do mesmo código-fonte, porque a wheel do PyPI traz um Arrow C++ próprio, e assim ficariam duas cópias do Arrow no container.

**SBOM.** As imagens publicadas têm attestations de SBOM (SPDX) e de provenance. Para ver: `docker buildx imagetools inspect docker.io/ndscprm/gdal:3.12.4-py3.12 --format '{{ json .SBOM }}'`. Os componentes que não vêm do apt (GDAL, Arrow, Thrift, xsimd, simdjson, Oracle Instant Client) e o RapidJSON, que vem do apt mas fica compilado dentro do `libarrow.so`, também ficam descritos em CycloneDX em `/opt/geosgb/share/sbom/`, dentro da imagem. Para analisar a imagem com o Grype, use a attestation (`grype sbom:<arquivo SPDX>`). Analisando a imagem direto, o Grype não lê esses arquivos. Outra opção é gerar o SBOM com `syft <imagem> --select-catalogers +sbom-cataloger -o spdx-json` e passá-lo ao Grype.

## Workflow reutilizável

O [oci-image.yml](.github/workflows/oci-image.yml) é um workflow reutilizável (`workflow_call`) para as imagens construídas sobre esta, como a [mapserver-oci](https://github.com/nds-cprm/mapserver-oci), a [mapproxy-oci](https://github.com/nds-cprm/mapproxy-oci) e a [pygeoapi-oci](https://github.com/nds-cprm/pygeoapi-oci). Ele segue o modelo do CI desta imagem:

1. **`prepare`**: resolve a versão (entrada `version` ou a linha `ARG <version-arg>=<versão>` do Dockerfile, validada por `version-pattern`) e confere as variantes.
2. **`build`**: um job por arquitetura, em runner nativo (`amd64` em `ubuntu-24.04` e `arm64` em `ubuntu-24.04-arm`, sem QEMU). Todas as variantes saem de uma única chamada do Bake, então os estágios que elas têm em comum são construídos uma vez só: a `-devel` e a release saem do mesmo build. As imagens são publicadas só por digest, com attestations de SBOM e de provenance, e o `test` de cada variante roda no próprio runner.
3. **`scan`**: Docker Scout e Grype nas variantes com `"scan": true`, antes de existir qualquer tag. Os relatórios vão para o code scanning (categorias `docker-scout-<variante>-<arch>` e `grype-<variante>-<arch>`). O Grype analisa a attestation de SBOM, que inclui os CycloneDX desta imagem em `/opt/geosgb/share/sbom`, então também enxerga o GDAL, o Arrow e o Thrift herdados, que o Scout ignora. Com `fail-on-severity`, uma vulnerabilidade com correção disponível, dessa severidade ou acima e fora do VEX, falha o job.
4. **`merge`**: cria as tags multiplataforma: a móvel (`tag` da variante) e a datada, `<tag>-<AAAAMMDD>` (UTC; `.2`, `.3`... nos builds seguintes do mesmo dia, nunca sobrescrita).

Uma falha no teste ou no scan de qualquer variante ou arquitetura impede a criação das tags. Com `push: false` (pull requests), as imagens só são construídas, carregadas no runner e testadas: sem scan, sem tags e sem os secrets.

Exemplo (o da mapserver-oci, com uma `-devel` e uma release):

```yaml
permissions:
  contents: read

jobs:
  image:
    uses: nds-cprm/gdal-oci/.github/workflows/oci-image.yml@main
    permissions:
      contents: read
      security-events: write   # SARIF para o code scanning (em repositório privado, também actions: read)
    secrets:
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
    with:
      image: docker.io/ndscprm/mapserver
      version-arg: MAPSERVER_VERSION
      variants: |
        [
          {"name": "devel", "target": "build", "tag": "{version}-devel",
           "test": "docker run --rm \"$IMAGE_REF\" mapserv -v | grep SUPPORTS=FASTCGI"},
          {"name": "release", "target": "release", "tag": "{version}", "scan": true, "cache-to": true,
           "test": "sh .github/scripts/smoke-test.sh \"$IMAGE_REF\""}
        ]
```

| Entrada | Padrão | Descrição |
|---|---|---|
| `image` | (obrigatória) | Repositório da imagem, sem tag (ex.: `docker.io/ndscprm/mapserver`) |
| `variants` | (obrigatória) | Array JSON, uma entrada por variante (campos abaixo) |
| `version-arg` | (obrigatória) | `ARG` do Dockerfile com a versão padrão, numa linha `ARG <nome>=<versão>` |
| `version` | vazio | Versão no lugar da do Dockerfile; também é passada como `--build-arg <version-arg>=<versão>` |
| `version-pattern` | `^[0-9]+\.[0-9]+\.[0-9]+$` | Expressão regular (ERE) que a versão precisa satisfazer |
| `context` / `dockerfile` | `.` / `Dockerfile` | Contexto do build e Dockerfile, relativo ao contexto |
| `build-args` | vazio | Build args extras, um `CHAVE=valor` por linha |
| `labels` | vazio | Labels extras, um `CHAVE=valor` por linha, com `{version}` substituído. `org.opencontainers.image.created`, `revision` e `source` são sempre definidos |
| `no-cache` | `false` | Ignora o cache (ex.: rebuild agendado, para pegar os pacotes atuais do apt e do pip) |
| `push` | `true` | `false` só constrói e testa |
| `dated-tags` | `true` | Cria também as tags `<tag>-<AAAAMMDD>` |
| `vex` | vazio | Arquivo OpenVEX para o Grype, relativo à raiz do repositório |
| `fail-on-severity` | vazio | `negligible`, `low`, `medium`, `high` ou `critical`: uma vulnerabilidade com correção disponível nessa severidade ou acima falha o scan. Vazio só reporta |
| `runners` | amd64 e arm64 nativos | Array JSON de `{"arch", "runner"}`, um job de build para cada |

Campos de cada variante:

| Campo | Descrição |
|---|---|
| `name` | Nome do alvo do Bake e da variante nos jobs, nos artifacts e nas categorias do SARIF (`[a-z0-9_-]`) |
| `tag` | Tag móvel, com `{version}` substituído (ex.: `{version}-devel`) |
| `target` | Estágio do Dockerfile. Sem ele, é construído o último estágio |
| `scan` | `true` para analisar a variante no job `scan` |
| `cache-to` | `true` na variante que grava o cache do GHA (`mode=max`). Dê à variante que passa por todos os estágios. Se nenhuma tiver, é a última |
| `no-cache-filters` | Estágios sempre reconstruídos, mesmo com cache (ex.: o do `apt-get install`, para pegar as correções do Debian) |
| `test` | Comando `bash` (`-euo pipefail`) rodado no runner depois do build, no checkout do repositório que chamou, com `IMAGE_REF` (a imagem por digest, ou `<image>:ci-<variante>-<arch>` com `push: false`), `VARIANT` e `ARCH` definidos |

O cache do GHA e os artifacts de digests levam o nome da imagem (`<nome>-<arch>`), então um repositório pode chamar o workflow para mais de uma imagem. As actions são fixadas por SHA de commit e atualizadas pelo Dependabot deste repositório. Uma mudança no workflow vale para todos os projetos que o chamam pelo mesmo `ref`: verifique-os antes de publicá-la.

## Licença

[Apache License 2.0](LICENSE). Os componentes incluídos na imagem têm licenças próprias, em especial o **Oracle Instant Client**, distribuído sob a licença da Oracle.
