# Exemplo: GeoDjango com PostGIS

Uma aplicação Django 5.2 LTS com `django.contrib.gis` sobre o `release` (`docker.io/ndscprm/gdal:3.12.4-py3.12`), usando PostGIS como banco. Não é preciso compilar nada: o GeoDjango carrega o **GDAL da imagem** e o **GEOS do Debian** via ctypes. A importação de dados aceita qualquer formato que o GDAL da imagem lê.

## Arquivos

| Arquivo | Descrição |
|---|---|
| [Dockerfile](Dockerfile) | Instala as dependências no venv da imagem, roda o `collectstatic` e confere que o Django carrega o GDAL/GEOS |
| [compose.yaml](compose.yaml) | PostGIS + aplicação, rodando com UID arbitrário |
| [requirements.txt](requirements.txt) | Django, psycopg e gunicorn |
| [geoapp/](geoapp/) | Projeto Django (`settings.py` configurado por variáveis de ambiente) |
| [places/](places/) | App com o modelo `Place` (`PointField`), admin com mapa, views e o comando `load_places` |
| [docker-entrypoint.d/20-django-migrate.sh](docker-entrypoint.d/20-django-migrate.sh) | Espera o banco e aplica as migrations na subida (com `DJANGO_MIGRATE=true`) |
| [data/places.geojson](data/places.geojson) | Cinco cidades de exemplo |

## Execução

```bash
docker compose up -d --build

# importa os dados de exemplo usando o GDAL
docker compose exec web python manage.py load_places data/places.geojson

curl localhost:8000/health
curl localhost:8000/places.geojson
curl "localhost:8000/places/near?lon=-43.17&lat=-22.90&km=500"

# admin com mapa: http://localhost:8000/admin/
docker compose exec web python manage.py createsuperuser

docker compose down -v
```

| Rota | O que faz |
|---|---|
| `/health` | Versões do GDAL, GEOS e PostGIS em uso |
| `/places.geojson` | Todos os lugares, em GeoJSON |
| `/places/near?lon=&lat=&km=` | Lugares a até `km` do ponto, ordenados por distância (consulta espacial no PostGIS) |
| `/admin/` | Admin do Django com edição no mapa (`GISModelAdmin`) |

### Importando dados com `load_places`

O comando abre a fonte com o `DataSource` do GeoDjango, ou seja, com o GDAL da imagem. Por isso aceita todos os drivers dela, inclusive conexões com bancos e serviços. As geometrias são reprojetadas para EPSG:4326.

```bash
python manage.py load_places dados.gpkg --layer cidades
python manage.py load_places pontos.kmz --name-field Name           # o LIBKML chama o campo de "Name"
python manage.py load_places "WFS:https://servidor/wfs" --layer camada
python manage.py load_places "OCI:usuario/senha@host:1521/servico:TABELA"
```

Foram testados GeoJSON, KMZ e um GeoPackage em EPSG:31983 (reprojetado na importação).

## Pontos importantes

- **O Django usa o GDAL da imagem.** O `settings.py` aponta `GDAL_LIBRARY_PATH` para `/opt/geosgb/lib/libgdal.so`. O GEOS (`libgeos_c`) já vem na imagem, porque o próprio GDAL depende dele.
- **`psycopg` sem o extra `[binary]`.** Ele usa o `libpq5` que já está na imagem, porque o driver PostGIS do GDAL depende dele, em vez de trazer uma segunda cópia da libpq.
- **Migrations pelo `/docker-entrypoint.d`.** O script [20-django-migrate.sh](docker-entrypoint.d/20-django-migrate.sh) é copiado com `755`, então o entrypoint da imagem base o **executa** em vez de carregá-lo. Ele só age com `DJANGO_MIGRATE=true` (o `compose.yaml` define esse valor). Assim, comandos avulsos como `docker run ... ogrinfo` não ficam esperando o banco. Em produção com várias réplicas, prefira rodar o `migrate` num job separado.
- **UID arbitrário.** O `compose.yaml` roda com `user: "12345:0"`. O nss_wrapper da imagem base cria o usuário virtual e o `HOME`. Os arquivos estáticos são gerados no build, então o container não precisa escrever em `/app`.
- **`docker compose exec` não passa pelo entrypoint.** Comandos via `exec` não têm o nss_wrapper ativo (`HOME=/`, UID sem nome). Para comandos que precisem dele, use `docker compose run --rm web <comando>`.
- **Configuração por variáveis de ambiente:** `DJANGO_SECRET_KEY`, `DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS`, `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `DJANGO_MIGRATE`. Os valores do `compose.yaml` servem só para demonstração.

Build args do Dockerfile:

| Arg | Padrão | Descrição |
|---|---|---|
| `GDAL_IMAGE` | `docker.io/ndscprm/gdal` | Repositório da imagem base |
| `GDAL_TAG` | `3.12.4-py3.12` | Tag do `release` |

O `compose.yaml` repassa as variáveis de ambiente `GDAL_IMAGE` e `GDAL_TAG` para esses build args.
