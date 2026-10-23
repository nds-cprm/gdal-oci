# TODO

Pendências das análises de segurança de outubro de 2026. Os itens resolvidos estão descritos no [CLAUDE.md](CLAUDE.md).

## Prioridade média

### Rodar como usuário não root
As imagens não definem `USER`, então rodam como root, e as imagens derivadas herdam isso. O exemplo [examples/django](examples/django/) só roda sem root porque o `compose.yaml` define `user: "12345:0"`; o Dockerfile dele não define `USER`.

- Criar no `release` um usuário fixo (ex.: `sgb`, UID 1000, GID 0), sem mudar para ele, para não quebrar imagens derivadas que fazem `pip install` ou `apt-get` no build.
- Documentar no README que a imagem derivada deve terminar com `USER 1000` (ou outro UID sem privilégios).
- Colocar `USER` nos Dockerfiles de [examples/](examples/), para servirem de modelo.
- O nss_wrapper continua necessário para UID arbitrário (OpenShift); com um usuário que existe no `/etc/passwd`, ele não entra em ação.

### Validar no CI os PRs do Dependabot
O workflow só roda manualmente ou pelo agendamento semanal (`push`/`pull_request` comentados), então os PRs do Dependabot (actions e `requirements/`) podem ser aceitos sem build nem smoke test. Uma quebra só aparece no build agendado seguinte, que nesse caso não publica tags, mas a imagem fica sem atualização até a correção.

- Adicionar um gatilho `pull_request` que rode só o `build` sem push (`push=false` ou `load`) e o smoke test, sem os jobs `scan` e `merge`.

### Tag datada robusta a falhas do registry
No job `merge`, o laço que escolhe o sufixo da tag datada (`<AAAAMMDD>`, `.2`, `.3`...) trata qualquer falha do `docker buildx imagetools inspect` como "a tag não existe". Uma falha momentânea do registry para uma tag que existe faria ela ser sobrescrita.

- Distinguir "not found" de outros erros (ex.: checar a mensagem ou o código de retorno) e falhar o job nos demais casos.

## Prioridade baixa

### Binários setuid no `release`
A `python:slim` traz 11 binários setuid/setgid (`su`, `mount`, `umount`, `passwd`, `chsh`, `chfn`, `newgrp`, `gpasswd`, `chage`, `expiry`, `unix_chkpwd`). Rodando como root não fazem diferença, mas com UID sem privilégios são caminho de escalada.

- Remover os bits no `release`: `find / -xdev -perm /6000 -type f -exec chmod a-s {} +`.
- Alternativa ou complemento: recomendar `--security-opt no-new-privileges` no README.

### Imagem `devel` fora do scan
O job `scan` verifica só o `release`. O `devel` também é publicado e recebe atualizações do Debian com menos frequência, já que nele o cache do CI vale.

- Escanear também o `devel`, só como relatório (sem gate), ou com o mesmo gate.

### Pacotes da imagem base no `release`
O estágio `release` é sempre refeito e instala os pacotes de runtime atuais, mas não roda `apt-get upgrade` nos pacotes que já vêm na `python:slim`. Entre uma correção do Debian e a próxima versão da imagem base, a correção fica de fora.

- Avaliar `apt-get upgrade -y` no `release`, no mesmo `RUN` do `apt-get install`.

### Exemplo Django
Em [examples/django](examples/django/):

- `settings.py` usa `"dev-only-insecure-key"` quando `DJANGO_SECRET_KEY` não é definido. Melhor falhar na inicialização.
- `compose.yaml` tem senhas fixas (`geoapp`) e `DJANGO_SECRET_KEY: change-me`. Para um exemplo é aceitável, mas vale um comentário indicando que são só para uso local.
