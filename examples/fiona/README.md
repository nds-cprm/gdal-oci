# Exemplo: fiona compilado contra o GDAL da imagem

A wheel do `fiona` no PyPI traz um GDAL próprio: a 1.10.1 vem com o GDAL 3.9.2. Instalada direto no `release`, ela deixaria duas cópias do GDAL no container, com versões e drivers diferentes. Este exemplo compila o `fiona` contra o GDAL da imagem. O mesmo vale para `rasterio` e outras bibliotecas que dependem do GDAL.

## Como funciona

1. **Estágio `build`**, a partir do `devel` (`docker.io/ndscprm/gdal:3.12.4-py3.12-devel`): estende o virtualenv `/opt/geosgb/venv` com `pip install --no-binary fiona` e as dependências do `requirements.txt`. Em seguida, confere que o `fiona` ficou ligado ao GDAL da imagem.
2. **Imagem final**, a partir do `release` (`docker.io/ndscprm/gdal:3.12.4-py3.12`): copia o venv estendido inteiro por cima do venv original.

Isso funciona porque o venv está no mesmo caminho nas duas imagens e as duas usam o mesmo Python. O venv estendido já contém tudo o que vinha na imagem (`osgeo`, numpy) mais os pacotes novos.

## Arquivos

| Arquivo | Descrição |
|---|---|
| [Dockerfile](Dockerfile) | Build em dois estágios (`devel` → `release`) |
| [requirements.txt](requirements.txt) | Dependências da aplicação, instaladas no mesmo venv |
| [app.py](app.py) | Mostra as versões e grava e relê um GeoPackage com o `fiona` |
| [.dockerignore](.dockerignore) | Deixa `__pycache__` fora da imagem |

## Build e execução

```bash
docker build -t fiona-gdal .
docker run --rm fiona-gdal
```

Saída esperada:

```
fiona 1.10.1 | GDAL do fiona: 3.12.4 | GDAL da imagem: 3.12.4
GeoPackage gravado e relido com 1 feição(ões); shapely 2.1.2
```

Build args:

| Arg | Padrão | Descrição |
|---|---|---|
| `GDAL_IMAGE` | `docker.io/ndscprm/gdal` | Repositório das imagens base |
| `GDAL_TAG` | `3.12.4-py3.12` | Tag do `release`. O `devel` usa a mesma tag com o sufixo `-devel` |
| `FIONA_VERSION` | `1.10.1` | Versão do fiona a compilar |

## Pontos importantes

- **O `devel` e o `release` precisam ser da mesma versão.** O Dockerfile monta as duas referências a partir do mesmo `GDAL_TAG`, então não dá para misturar versões sem querer. Um venv compilado num build e copiado para a imagem de outro build pode não bater com o GDAL e o numpy dela.
- **O `COPY` substitui o venv do `release` inteiro.** Todas as dependências Python precisam ser instaladas no estágio `build`. Um `pip install` no estágio final *antes* do `COPY` é perdido. Depois do `COPY`, ainda dá para instalar pacotes que não compilam nada.
- **Para outras bibliotecas que dependem do GDAL**, use o mesmo `--no-binary`. Exemplo: `--no-binary fiona,rasterio`.
- **Fixe as versões** (`FIONA_VERSION`, `requirements.txt`). Como o pacote é compilado, uma versão nova pode exigir um GDAL ou um numpy diferente.
- **Mantenha a verificação com `assert`.** Se uma dependência do `requirements.txt` reinstalar o `fiona` a partir da wheel, o build falha em vez de gerar uma imagem com dois GDAL.
- **O fiona tem uma lista própria de drivers liberados** (`fiona.supported_drivers`). Ela não inclui todos os drivers do GDAL; o `OCI`, por exemplo, não está nela.
