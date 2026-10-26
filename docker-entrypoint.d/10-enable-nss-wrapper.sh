#!/bin/sh

# Obtém o UID do usuário que está executando o container
USER_ID=$(id -u)
GROUP_ID=$(id -g)

USER_NAME=${USER_NAME:-sgb}

# Se o UID atual não existir no /etc/passwd do container
if [ "$USER_ID" != "0" ] && ! getent passwd "$USER_ID" >/dev/null 2>&1; then

    # O Docker define HOME=/ quando o UID não existe no passwd; /tmp passa a ser padrão.
    # Um HOME não gravável é mantido: com --read-only ele nunca é, e imagens derivadas guardam a configuração nele
    if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
        export HOME=/tmp
    fi

    # USER_NAME e HOME vão para uma linha do passwd virtual: ":" ou quebra de linha injetariam campos ou
    # linhas. Nome no formato portável (letra ou "_" no início, depois letras, dígitos, ".", "_" ou "-")
    NL='
'
    case "$USER_NAME" in
        "" | [!A-Za-z_]* | *[!A-Za-z0-9._-]*)
            echo "nss_wrapper: USER_NAME inválido: '${USER_NAME}' (use letras, dígitos, '.', '_' ou '-', começando por letra ou '_')" >&2
            exit 1 ;;
    esac
    if [ "${#USER_NAME}" -gt 32 ]; then
        echo "nss_wrapper: USER_NAME com mais de 32 caracteres: '${USER_NAME}'" >&2
        exit 1
    fi
    case "$HOME" in
        *:* | *"$NL"*)
            echo "nss_wrapper: HOME com ':' ou quebra de linha não pode ir para o passwd: '${HOME}'" >&2
            exit 1 ;;
    esac

    # Arquivos virtuais num diretório novo e exclusivo (mktemp cria com 0700 e falha se o nome já existir):
    # caminhos fixos no /tmp poderiam ter sido plantados antes, ex.: symlink num /tmp compartilhado entre containers
    if ! NSS_WRAPPER_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nss_wrapper.XXXXXX"); then
        echo "nss_wrapper: não foi possível criar o diretório temporário em ${TMPDIR:-/tmp}" >&2
        exit 1
    fi
    export NSS_WRAPPER_PASSWD="${NSS_WRAPPER_DIR}/passwd"
    export NSS_WRAPPER_GROUP="${NSS_WRAPPER_DIR}/group"

    # Copia a base existente para os arquivos virtuais
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
