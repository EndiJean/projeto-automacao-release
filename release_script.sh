set -e

DIRETORIO_DO_SCRIPT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" # Obtém o diretório absoluto do script.
RELEASE_BRANCH="release" # branch principal.
DEVELOPMENT_BRANCH="desenvolvimento" # branch de desenvolvimento
VERSION_FILE="versao" # nome do arquivo de texto com a versão
PROJECT_NAME="artifactId" # Usado para obter o artifactId do pom.xml

# Função para checar o status do Git e pausar se houver alterações
verifica_pendencias() {
    if [[ $(git status --porcelain) ]]; then
        echo "--------------------------------------------------------"
        echo "ATENÇÃO: Existem alterações pendentes (modificações ou conflitos) no seu diretório de trabalho."
        echo "Por favor, resolva os conflitos (se houver) e faça commit de TODAS as alterações."
        echo "Após resolver e commitar, pressione Enter para continuar..."
        echo "--------------------------------------------------------"
        read -r # Espera o usuário pressionar Enter
        # Verifica novamente após o usuário continuar
        verifica_pendencias
    fi
}

# Função para executar um merge e lidar com conflitos (para merges de feature/fix)
fazer_merge_e_push_branch() {
    BRANCH_TO_MERGE_REMOTE="$1" # Esta é a branch remota, ex: "origin/feature/xyz"
    CURRENT_WORKING_BRANCH="$2" # A branch local onde o merge será feito (ex: release)

    echo "--------------------------------------------------------"
    echo "-> Tentando fazer merge de '$BRANCH_TO_MERGE_REMOTE' para '$CURRENT_WORKING_BRANCH'..."
    if git merge --no-ff "$BRANCH_TO_MERGE_REMOTE" -m "Merge branch '$BRANCH_TO_MERGE_REMOTE' into $CURRENT_WORKING_BRANCH for release"; then
        echo "Merge de '$BRANCH_TO_MERGE_REMOTE' realizado com sucesso."
    else
        echo "--------------------------------------------------------"
        echo "CONFLITO DE MERGE DETECTADO ao mesclar '$BRANCH_TO_MERGE_REMOTE' em '$CURRENT_WORKING_BRANCH'."
        echo "Por favor, resolva os conflitos manualmente e faça um commit de merge."
        echo "Comandos úteis: git status, git diff, git add, git commit -m 'Merge de $BRANCH_TO_MERGE_REMOTE resolvido'."
        echo "Após resolver o conflito e commitar, pressione Enter para continuar..."
        echo "--------------------------------------------------------"
        read -r
        verifica_pendencias
        echo "Conflito de '$BRANCH_TO_MERGE_REMOTE' resolvido e commited."
    fi

    echo "-> Fazendo push das alterações de merge para '$CURRENT_WORKING_BRANCH'..."
    git push origin "$CURRENT_WORKING_BRANCH" || { echo "Falha ao fazer push da branch $CURRENT_WORKING_BRANCH após merge de $BRANCH_TO_MERGE_REMOTE. Abortando."; exit 1; }
    echo "Push do merge de '$BRANCH_TO_MERGE_REMOTE' realizado com sucesso."
}

echo "======================================================"
echo "          Iniciando Processo de Versão                "
echo "======================================================"

verifica_pendencias

# 1. Checkout para a branch de release e pull (e fetch de todas as remota)
echo "-> Checkout para a branch de release ('$RELEASE_BRANCH') e realizando pull..."
git checkout "$RELEASE_BRANCH" || { echo "Falha ao mudar para a branch $RELEASE_BRANCH. Abortando."; exit 1; }
git pull origin "$RELEASE_BRANCH" || { echo "Falha ao puxar da branch $RELEASE_BRANCH. Abortando."; exit 1; }

# Traz todas as referências remotas para o repositório local
echo "-> Atualizando referências de branches remotas (git fetch origin)..."
git fetch origin || { echo "Falha ao buscar branches remotas. Verifique a conexão e permissões."; exit 1; }

# 2. Garante que o repositório está limpo antes de iniciar os merges
echo "-> Verificando status inicial do Git..."
verifica_pendencias

# 3. Loop para informar as branches a serem mescladas na RELEASE_BRANCH
MERGE_BRANCHES_REMOTE=()
while true; do
    echo "--------------------------------------------------------"
    read -p "Informe o NOME da branch remota (sem 'origin/') para fazer merge na '$RELEASE_BRANCH' (ou deixe em branco para finalizar): " BRANCH_INPUT_NAME
    if [ -z "$BRANCH_INPUT_NAME" ]; then
        break
    fi

    REMOTE_BRANCH_FULL_REF="origin/$BRANCH_INPUT_NAME"

    # Verifica se a branch remota existe
    if git branch -r | grep -q "origin/$BRANCH_INPUT_NAME$"; then
        MERGE_BRANCHES_REMOTE+=("$REMOTE_BRANCH_FULL_REF")
        echo "Branch remota '$REMOTE_BRANCH_FULL_REF' adicionada para merge."
    else
        echo "AVISO: Branch remota '$REMOTE_BRANCH_FULL_REF' NÃO encontrada. Por favor, verifique o nome e se já foi feito push para o remoto."
    fi
done

if [ ${#MERGE_BRANCHES_REMOTE[@]} -eq 0 ]; then
    echo "Nenhuma branch informada para merge. Abortando a release."
    exit 1
fi

echo "--------------------------------------------------------"
echo "As seguintes branches REMOTAS serão mescladas uma a uma na '$RELEASE_BRANCH':"
for branch in "${MERGE_BRANCHES_REMOTE[@]}"; do
    echo "  - $branch"
done

read -p "
Pressione Enter para iniciar os merges..."
echo "--------------------------------------------------------"

# 4. Executar merges sequencialmente com push após cada um
echo "-> Iniciando processo de merge e push de cada branch remota informada..."
for branch_to_merge_remote in "${MERGE_BRANCHES_REMOTE[@]}"; do
    fazer_merge_e_push_branch "$branch_to_merge_remote" "$RELEASE_BRANCH"
    echo "--------------------------------------------------------"
    read -p "Merge e push de '$branch_to_merge_remote' concluído. Pressione Enter para continuar para a próxima branch (se houver) ou finalizar merges..."
    echo "--------------------------------------------------------"
done

echo "Todos os merges solicitados foram concluídos e enviados para o repositório remoto."

# 5. Solicitar APENAS a versão de release
echo "--------------------------------------------------------"
# Obtém a versão atual do POM
CURRENT_POM_VERSION=$(mvn -f "$DIRETORIO_DO_SCRIPT/pom.xml" help:evaluate -Dexpression=project.version -q -DforceStdout 2>/dev/null | sed 's/-SNAPSHOT//')
if [[ -z "$CURRENT_POM_VERSION" ]]; then
    echo "AVISO: Não foi possível obter a versão atual do POM. Por favor, informe a versão manualmente."
    CURRENT_POM_VERSION="1.0.0" # Sugestão padrão se não conseguir ler
fi

read -p "Informe a nova versão da Branch release (ex: $CURRENT_POM_VERSION): " RELEASE_VERSION
RELEASE_VERSION=${RELEASE_VERSION:-$CURRENT_POM_VERSION}

echo "-> Versão de Release Definida: $RELEASE_VERSION"
echo "--------------------------------------------------------"

## 6. Alterar a versão no pom.xml, no arquivo de versão e commitar
echo "-> Atualizando pom.xml para a versão de release: $RELEASE_VERSION"

CAMINHO_COMPLETO_ARQUIVO_VERSAO="$DIRETORIO_DO_SCRIPT/$VERSION_FILE"

# Verifica se o arquivo de versão existe antes de tentar alterar
if [ -f "$CAMINHO_COMPLETO_ARQUIVO_VERSAO" ]; then
    echo "-> Atualizando arquivo de versão '$CAMINHO_COMPLETO_ARQUIVO_VERSAO' para: $RELEASE_VERSION"
    echo "$RELEASE_VERSION" > "$CAMINHO_COMPLETO_ARQUIVO_VERSAO" || { echo "Falha ao atualizar o arquivo de versão '$VERSION_FILE'. Abortando."; exit 1; }
    git add "$CAMINHO_COMPLETO_ARQUIVO_VERSAO" # Adiciona o arquivo de versão ao staging
else
    echo "AVISO: Arquivo de versão '$VERSION_FILE' não encontrado na raiz do projeto ($DIRETORIO_DO_SCRIPT). Não foi possível atualizá-lo."
fi

# Atualiza a versão principal no pom.xml
mvn -f "$DIRETORIO_DO_SCRIPT/pom.xml" versions:set -DnewVersion="$RELEASE_VERSION" -DgenerateBackupPoms=false || { echo "Falha ao setar versão no POM. Abortando."; exit 1; }

git add "$DIRETORIO_DO_SCRIPT/pom.xml"

# PAUSA ADICIONADA: Após as alterações no pom.xml e antes do commit
echo "--------------------------------------------------------"
echo "VERIFICAÇÃO: Versões alteradas localmente. Verifique se está tudo correto antes do commit."
read -p "Pressione Enter para continuar..."
echo "--------------------------------------------------------"

git commit -m "Atualizacao de versao: $RELEASE_VERSION" || { echo "Falha ao commitar versão de release. Abortando."; exit 1; }

echo "-> Fazendo push do commit de atualização de versão para '$RELEASE_BRANCH'..."
git push origin "$RELEASE_BRANCH" || { echo "Falha ao fazer push da branch $RELEASE_BRANCH. Abortando."; exit 1; }

## 7. Executar o build do Maven para gerar o JAR e processar arquivos
echo "-> Executando build do Maven (clean package)..."
(cd "$DIRETORIO_DO_SCRIPT" && mvn clean package) || { echo "Falha no build do Maven. Abortando."; exit 1; }

## 8. Copiar o JAR gerado e gerenciar pastas
echo "--------------------------------------------------------"
echo "-> Iniciando processo de cópia do JAR e da pasta 'lib' (se existir)..."

# Obtém informações do POM para determinar o nome do JAR gerado dinamicamente
ID_DO_ARTEFATO=$(mvn -f "$DIRETORIO_DO_SCRIPT/pom.xml" help:evaluate -Dexpression=project.artifactId -q -DforceStdout 2>/dev/null)
VERSAO_DO_PROJETO=$(mvn -f "$DIRETORIO_DO_SCRIPT/pom.xml" help:evaluate -Dexpression=project.version -q -DforceStdout 2>/dev/null)
EMPACOTAMENTO_DO_PROJETO=$(mvn -f "$DIRETORIO_DO_SCRIPT/pom.xml" help:evaluate -Dexpression=project.packaging -q -DforceStdout 2>/dev/null)
NOME_FINAL_DO_BUILD=$(mvn -f "$DIRETORIO_DO_SCRIPT/pom.xml" help:evaluate -Dexpression=project.build.finalName -q -DforceStdout 2>/dev/null)

# Determina o nome base do JAR que será gerado, respeitando a tag <finalName> se houver
if [[ -n "$NOME_FINAL_DO_BUILD" && "$NOME_FINAL_DO_BUILD" != "\${project.artifactId}-\${project.version}" ]]; then
    BASE_NOME_JAR_GERADO="${NOME_FINAL_DO_BUILD}"
else
    BASE_NOME_JAR_GERADO="${ID_DO_ARTEFATO}-${VERSAO_DO_PROJETO}"
fi

# Tenta encontrar o JAR gerado no diretório 'target' do projeto
# Prioriza o nome exato ou com sufixos comuns de plugins (ex: -jar-with-dependencies)
CAMINHO_JAR_GERADO_ORIGEM=$(find "$DIRETORIO_DO_SCRIPT/target" -maxdepth 1 -name "${BASE_NOME_JAR_GERADO}*.${EMPACOTAMENTO_DO_PROJETO}" | head -n 1)

# Verifica se um JAR foi encontrado (e adiciona uma busca mais genérica se a primeira falhar)
if [ -z "$CAMINHO_JAR_GERADO_ORIGEM" ]; then
    echo "AVISO: Não foi possível encontrar o JAR com o nome padrão ('${BASE_NOME_JAR_GERADO}*.${EMPACOTAMENTO_DO_PROJETO}')."
    echo "Tentando encontrar o arquivo .$EMPACOTAMENTO_DO_PROJETO mais recente em '$DIRETORIO_DO_SCRIPT/target/'..."
    CAMINHO_JAR_GERADO_ORIGEM=$(ls -t "$DIRETORIO_DO_SCRIPT/target"/*.${EMPACOTAMENTO_DO_PROJETO} 2>/dev/null | head -n 1)
fi

if [ -f "$CAMINHO_JAR_GERADO_ORIGEM" ]; then
    NOME_DO_ARQUIVO_JAR=$(basename "$CAMINHO_JAR_GERADO_ORIGEM")
    NOME_BASE_DO_JAR_SEM_EXT=$(basename "$NOME_DO_ARQUIVO_JAR" ".${EMPACOTAMENTO_DO_PROJETO}")
    
    echo "-> JAR gerado encontrado: '$NOME_DO_ARQUIVO_JAR'."

    DESTINO_PASTA_VERSOES="C:/versoes/$NOME_BASE_DO_JAR_SEM_EXT"

    # --- Cópia para C:/versoes/{nome_do_jar}/ ---
    echo "-> Criando pasta de destino em '$DESTINO_PASTA_VERSOES'..."
    mkdir -p "$DESTINO_PASTA_VERSOES" || { echo "Falha ao criar a pasta '$DESTINO_PASTA_VERSOES'. Verifique as permissões."; exit 1; }

    echo "-> Copiando '$NOME_DO_ARQUIVO_JAR' para '$DESTINO_PASTA_VERSOES'..."
    cp "$CAMINHO_JAR_GERADO_ORIGEM" "$DESTINO_PASTA_VERSOES/$NOME_DO_ARQUIVO_JAR" || { echo "Falha ao copiar o JAR para '$DESTINO_PASTA_VERSOES'. Abortando."; exit 1; }
    echo "-> JAR copiado para '$DESTINO_PASTA_VERSOES/$NOME_DO_ARQUIVO_JAR'."

    # --- Verificação e cópia da pasta 'lib' (se existir ao lado do JAR original) ---
    CAMINHO_PASTA_LIB_ORIGEM="$(dirname "$CAMINHO_JAR_GERADO_ORIGEM")/lib"
    
    if [ -d "$CAMINHO_PASTA_LIB_ORIGEM" ]; then
        echo "-> Pasta 'lib' encontrada em '$CAMINHO_PASTA_LIB_ORIGEM'."

        # Copiar para a pasta de versões
        echo "-> Copiando pasta 'lib' para '$DESTINO_PASTA_VERSOES'..."
        cp -R "$CAMINHO_PASTA_LIB_ORIGEM" "$DESTINO_PASTA_VERSOES/" || { echo "Falha ao copiar a pasta 'lib' para '$DESTINO_PASTA_VERSOES'. Abortando."; exit 1; }
        echo "-> Pasta 'lib' copiada para '$DESTINO_PASTA_VERSOES/lib'."

    else
        echo "AVISO: Pasta 'lib' não encontrada ao lado do JAR gerado em '$CAMINHO_PASTA_LIB_ORIGEM'. Nenhuma pasta 'lib' será copiada."
    fi
else
    echo "ERRO: Nenhum arquivo .$EMPACOTAMENTO_DO_PROJETO foi encontrado em '$DIRETORIO_DO_SCRIPT/target/' após o build."
    echo "Verifique o pom.xml e a saída do build do Maven para garantir que o JAR está sendo gerado."
    exit 1
fi

read -p "Deseja criar Tag (s/N): " CRIAR_TAG
    CRIAR_TAG=${CRIAR_TAG:-n}

# 9. Criar a tag Git para a release e fazer push da tag
if [[ "$CRIAR_TAG" =~ ^[Ss]$ ]]; then
    echo "-> Criando tag Git: $RELEASE_VERSION"
    git tag "$RELEASE_VERSION" || { echo "Falha ao criar tag Git. Abortando."; exit 1; }

    echo "-> Fazendo push da tag '$RELEASE_VERSION' para o repositório remoto..."
    git push origin "$RELEASE_VERSION" || { echo "Falha ao fazer push da tag '$RELEASE_VERSION'. Abortando."; exit 1; }
    echo "-> Push da tag '$RELEASE_VERSION' realizado com sucesso."
fi

# 10. Checkout para a branch de desenvolvimento, pull e merge da branch de release
read -p "Realizar merge na desenvolvimento (s/N): " MERGE_DESENVOLVIMENTO
    MERGE_DESENVOLVIMENTO=${MERGE_DESENVOLVIMENTO:-n}

if [[ "$MERGE_DESENVOLVIMENTO" =~ ^[Ss]$ ]]; then
    echo "--------------------------------------------------------"
    echo "-> Iniciando merge da branch '$RELEASE_BRANCH' na branch '$DEVELOPMENT_BRANCH'..."

    # Salva a branch atual para poder voltar depois
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    # 10a. Checkout para a branch de desenvolvimento
    echo "-> Checkout para a branch '$DEVELOPMENT_BRANCH'..."
    git checkout "$DEVELOPMENT_BRANCH" || { echo "Falha ao mudar para a branch $DEVELOPMENT_BRANCH. Abortando merge final."; exit 1; }

    # 10b. Realiza um pull para garantir que a branch de desenvolvimento esteja atualizada
    echo "-> Realizando pull da branch '$DEVELOPMENT_BRANCH'..."
    git pull origin "$DEVELOPMENT_BRANCH" || { echo "Falha ao puxar da branch $DEVELOPMENT_BRANCH. Abortando merge final."; exit 1; }

    # 10c. Garante que a branch de desenvolvimento esteja limpa antes do merge
    echo "-> Verificando status do Git na branch '$DEVELOPMENT_BRANCH' antes do merge final..."
    verifica_pendencias # Reutiliza a função de verificação de pendências

    # 10d. Faz o merge da branch de release na branch de desenvolvimento
    echo "-> Fazendo merge da branch '$RELEASE_BRANCH' na '$DEVELOPMENT_BRANCH'..."
    if git merge --no-ff "$RELEASE_BRANCH" -m "Merge branch '$RELEASE_BRANCH' into $DEVELOPMENT_BRANCH after release $RELEASE_VERSION"; then
        echo "Merge da '$RELEASE_BRANCH' na '$DEVELOPMENT_BRANCH' realizado com sucesso."
    else
        echo "--------------------------------------------------------"
        echo "CONFLITO DE MERGE DETECTADO ao mesclar '$RELEASE_BRANCH' na '$DEVELOPMENT_BRANCH'."
        echo "Por favor, resolva os conflitos manualmente na '$DEVELOPMENT_BRANCH' e faça um commit de merge."
        echo "Comandos úteis: git status, git diff, git add, git commit -m 'Merge da $RELEASE_BRANCH resolvido'."
        echo "Após resolver o conflito e commitar, pressione Enter para continuar..."
        echo "--------------------------------------------------------"
        read -r # Espera o usuário pressionar Enter
        verifica_pendencias # Verifica se o conflito foi realmente resolvido e commited
        echo "Conflito de merge da '$RELEASE_BRANCH' na '$DEVELOPMENT_BRANCH' resolvido e commited."
    fi

    # 10e. Faz push da branch de desenvolvimento atualizada
    echo "-> Fazendo push da branch '$DEVELOPMENT_BRANCH' para o repositório remoto..."
    git push origin "$DEVELOPMENT_BRANCH" || { echo "Falha ao fazer push da branch $DEVELOPMENT_BRANCH após merge final. Abortando."; exit 1; }
    echo "Push da '$DEVELOPMENT_BRANCH' realizado com sucesso."

    # Retorna para a branch de release
    git checkout "$RELEASE_BRANCH" || { echo "AVISO: Falha ao retornar para a branch '$RELEASE_BRANCH'. Permaneceu em $DEVELOPMENT_BRANCH."; }
fi

echo "======================================================"
echo "    Processo de Release Concluído com Sucesso!        "
echo "        Versão Lançada: $RELEASE_VERSION              "
echo "======================================================"