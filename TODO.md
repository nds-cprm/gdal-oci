# TODO

Pendências das análises de segurança de outubro de 2026. Os itens resolvidos estão descritos no [CLAUDE.md](CLAUDE.md).

## Prioridade média

### Rodar como usuário não root
As imagens não definem `USER`, então rodam como root, e as imagens derivadas herdam isso. O exemplo [examples/django](examples/django/) só roda sem root porque o `compose.yaml` define `user: "12345:0"`; o Dockerfile dele não define `USER`.

- Criar no `release-py` um usuário fixo (ex.: `sgb`, UID 1000, GID 0), sem mudar para ele, para não quebrar imagens derivadas que fazem `pip install` ou `apt-get` no build.
- Documentar no README que a imagem derivada deve terminar com `USER 1000` (ou outro UID sem privilégios).
- Colocar `USER` nos Dockerfiles de [examples/](examples/), para servirem de modelo.
- O nss_wrapper continua necessário para UID arbitrário (OpenShift); com um usuário que existe no `/etc/passwd`, ele não entra em ação.

### Validar no CI os PRs do Dependabot
O workflow só roda manualmente ou pelo agendamento semanal (`push`/`pull_request` comentados), então os PRs do Dependabot (actions e `requirements/`) podem ser aceitos sem build nem smoke test. Uma quebra só aparece no build agendado seguinte, que nesse caso não publica tags, mas a imagem fica sem atualização até a correção.

- Adicionar ao [publish-image.yml](.github/workflows/publish-image.yml) um gatilho `pull_request` que chame o reutilizável com `push: false` (só build e smoke test, sem scan, tags, secrets nem `dispatch`).

### Tag datada robusta a falhas do registry
No job `merge` do [reusable-publish-image.yml](.github/workflows/reusable-publish-image.yml), o laço que escolhe o sufixo da tag datada (`<AAAAMMDD>`, `.2`, `.3`...) trata qualquer falha do `docker buildx imagetools inspect` como "a tag não existe". Uma falha momentânea do registry para uma tag que existe faria ela ser sobrescrita. O laço vale para esta imagem e para as derivadas.

- Distinguir "not found" de outros erros (ex.: checar a mensagem ou o código de retorno) e falhar o job nos demais casos.

### Versionar o workflow reutilizável
As imagens derivadas chamam o [reusable-publish-image.yml](.github/workflows/reusable-publish-image.yml) por `@main`, então qualquer commit no `main` muda o CI de todas na hora, sem revisão do lado delas. Esta imagem usa a cópia do mesmo commit (`./.github/workflows/...`), então o build da base testa cada mudança, mas só no próximo run.

- Criar uma tag (ex.: `reusable-publish-image-v1`) e trocar os `uses:` dos projetos por ela, ou pelo SHA do commit com a tag em comentário, para o Dependabot deles (ecossistema `github-actions`) propor as atualizações.

## Prioridade baixa

### Binários setuid no `release-py`
A `python:slim` traz 11 binários setuid/setgid (`su`, `mount`, `umount`, `passwd`, `chsh`, `chfn`, `newgrp`, `gpasswd`, `chage`, `expiry`, `unix_chkpwd`). Rodando como root não fazem diferença, mas com UID sem privilégios são caminho de escalada.

- Remover os bits no `release-py`: `find / -xdev -perm /6000 -type f -exec chmod a-s {} +`.
- Alternativa ou complemento: recomendar `--security-opt no-new-privileges` no README.

### Análises antigas no code scanning
Com a migração para o workflow reutilizável, as categorias de SARIF mudaram de `docker-scout-<arch>`, `grype-<arch>`, `docker-scout-nopy-<arch>` e `grype-nopy-<arch>` para `docker-scout-<variante>-<arch>` e `grype-<variante>-<arch>`. As análises das categorias antigas não são mais atualizadas, e os alertas delas continuam abertos.

- Depois do primeiro build com as categorias novas, apagar as análises antigas: listar com `gh api repos/nds-cprm/gdal-oci/code-scanning/analyses --paginate -q '.[] | [.id, .category] | @tsv'` e apagar com `gh api -X DELETE "repos/nds-cprm/gdal-oci/code-scanning/analyses/<id>?confirm_delete=true"`. A API só apaga a análise mais recente de cada categoria por vez e devolve a seguinte em `next_analysis_url`/`confirm_delete_url`, então é preciso repetir até esvaziar a categoria.

### Imagem `devel` fora do scan
Só o `release-py` e o `release-nopy` têm `scan: true` nas variantes do [publish-image.yml](.github/workflows/publish-image.yml). O `devel` também é publicado e recebe atualizações do Debian com menos frequência, já que nele o cache do CI vale.

- Escanear também o `devel` (`scan: true` no job `meta`), com o mesmo gate. Para só reportar, o reutilizável precisaria de um gate por variante.

### Exemplo Django
Em [examples/django](examples/django/):

- `settings.py` usa `"dev-only-insecure-key"` quando `DJANGO_SECRET_KEY` não é definido. Melhor falhar na inicialização.
- `compose.yaml` tem senhas fixas (`geoapp`) e `DJANGO_SECRET_KEY: change-me`. Para um exemplo é aceitável, mas vale um comentário indicando que são só para uso local.
