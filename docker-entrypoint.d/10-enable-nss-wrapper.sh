#!/bin/sh

# Obtém o UID do usuário que está executando o container
USER_ID=$(id -u)
GROUP_ID=$(id -g)

USER_NAME=${USER_NAME:-sgb}

# Se o UID atual não existir no /etc/passwd do container
if [ "$USER_ID" != "0" ] && ! getent passwd "$USER_ID" >/dev/null 2>&1; then

    # O Docker define HOME=/ quando o UID não existe no passwd; usa /tmp se o HOME não for gravável
    if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ] || [ ! -w "$HOME" ]; then
        export HOME=/tmp
    fi

    # Define caminhos para os arquivos virtuais no /tmp (diretório sempre gravável)
    export NSS_WRAPPER_PASSWD=/tmp/passwd
    export NSS_WRAPPER_GROUP=/tmp/group

    # Copia a base existente para o arquivo temporário
    cat /etc/passwd > "$NSS_WRAPPER_PASSWD"
    cat /etc/group > "$NSS_WRAPPER_GROUP"

    # Injeta dinamicamente o UID aleatório mapeando para o nome ${USER_NAME}
    echo "${USER_NAME}:x:${USER_ID}:${GROUP_ID}:App User:${HOME}:/bin/false" >> "$NSS_WRAPPER_PASSWD"

    # Ativa o nss_wrapper interceptando as chamadas do sistema
    export LD_PRELOAD=libnss_wrapper.so

    # stderr, para não misturar com a saída do comando do container (ex.: /vsistdout/)
    if [ -z "${ENTRYPOINT_QUIET_LOGS:-}" ]; then
        echo "nss_wrapper ativado: Usuário virtual '${USER_NAME}' criado para o UID ${USER_ID}" >&2
    fi
fi