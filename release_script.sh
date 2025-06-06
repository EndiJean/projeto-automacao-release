#!/bin/bash
set -e # Sai imediatamente se um comando retornar um status de saída diferente de zero

# --- Configurações Fixas ---
RELEASE_BRANCH="release" # Sua branch principal de release. Todo o processo será feito AQUI.
VERSION_FILE="versao" # O nome do seu arquivo de texto com a versão

# --- Funções Auxiliares ---

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
        if [[ $(git status --porcelain) ]]; then
            echo "ERRO: O diretório de trabalho ainda não está limpo. Abortando a release."
            exit 1
        fi
    fi
}

# Função para executar um merge e lidar com conflitos
fazer_merge_e_push() {
    BRANCH_TO_MERGE_REMOTE="$1" # Esta é a branch remota, ex: "origin/feature/xyz"
    echo "--------------------------------------------------------"
    echo "-> Tentando fazer merge de '$BRANCH_TO_MERGE_REMOTE' para '$RELEASE_BRANCH'..."
    if git merge --no-ff "$BRANCH_TO_MERGE_REMOTE" -m "Merge branch '$BRANCH_TO_MERGE_REMOTE' into $RELEASE_BRANCH for release"; then
        echo "Merge de '$BRANCH_TO_MERGE_REMOTE' realizado com sucesso."
    else
        echo "--------------------------------------------------------"
        echo "CONFLITO DE MERGE DETECTADO ao mesclar '$BRANCH_TO_MERGE_REMOTE'."
        echo "Por favor, resolva os conflitos manualmente e faça um commit de merge."
        echo "Comandos úteis: git status, git diff, git add, git commit -m 'Merge de $BRANCH_TO_MERGE_REMOTE resolvido'."
        echo "Após resolver o conflito e commitar, pressione Enter para continuar..."
        echo "--------------------------------------------------------"
        read -r # Espera o usuário pressionar Enter
        verifica_pendencias # Verifica se o conflito foi realmente resolvido e commited
        echo "Conflito de '$BRANCH_TO_MERGE_REMOTE' resolvido e commited."
    fi

    echo "-> Fazendo push das alterações de merge para '$RELEASE_BRANCH'..."
    git push origin "$RELEASE_BRANCH" || { echo "Falha ao fazer push da branch $RELEASE_BRANCH após merge de $BRANCH_TO_MERGE_REMOTE. Abortando."; exit 1; }
    echo "Push do merge de '$BRANCH_TO_MERGE_REMOTE' realizado com sucesso."
}

# --- Início do Script Principal ---
echo "======================================================"
echo "      Iniciando Processo de Release Automatizado      "
echo "======================================================"

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

# 3. Loop para informar as branches a serem mescladas
MERGE_BRANCHES_REMOTE=()
while true; do
    echo "--------------------------------------------------------"
    read -p "Informe o NOME da branch remota (sem 'origin/') para fazer merge na '$RELEASE_BRANCH' (ou deixe em branco para finalizar): " BRANCH_INPUT_NAME
    if [ -z "$BRANCH_INPUT_NAME" ]; then
        break # Sai do loop se a entrada estiver vazias
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
echo "--------------------------------------------------------"

# 4. Executar merges sequencialmente com push após cada um
echo "-> Iniciando processo de merge e push de cada branch remota informada..."
for branch_to_merge_remote in "${MERGE_BRANCHES_REMOTE[@]}"; do
    fazer_merge_e_push "$branch_to_merge_remote" # Chama a função que lida com o merge e push
    echo "--------------------------------------------------------"
    read -p "Merge e push de '$branch_to_merge_remote' concluído. Pressione Enter para continuar para a próxima branch (se houver)..."
    echo "--------------------------------------------------------"
done

echo "Todos os merges solicitados foram concluídos e enviados para o repositório remoto."

# 5. Solicitar APENAS a versão de release
echo "--------------------------------------------------------"
# Obtém a versão atual do POM
CURRENT_POM_VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout 2>/dev/null | sed 's/-SNAPSHOT//')
if [[ -z "$CURRENT_POM_VERSION" ]]; then
    echo "AVISO: Não foi possível obter a versão atual do POM. Por favor, informe a versão manualmente."
    CURRENT_POM_VERSION="1.0.0" # Sugestão padrão se não conseguir ler
fi

read -p "Informe a VERSÃO DE RELEASE (ex: $CURRENT_POM_VERSION): " RELEASE_VERSION
RELEASE_VERSION=${RELEASE_VERSION:-$CURRENT_POM_VERSION} # Usa a sugestão se a entrada for vazia

echo "-> Versão de Release Definida: $RELEASE_VERSION"
echo "--------------------------------------------------------"

# 6. Alterar a versão no pom.xml para a versão de release
echo "-> Atualizando pom.xml para a versão de release: $RELEASE_VERSION"

# Verifica se o arquivo de versão existe antes de tentar alterar
if [ -f "$VERSION_FILE" ]; then
    echo "-> Atualizando arquivo de versão '$VERSION_FILE' para: $RELEASE_VERSION"
    echo "$RELEASE_VERSION" > "$VERSION_FILE" || { echo "Falha ao atualizar o arquivo de versão '$VERSION_FILE'. Abortando."; exit 1; }
    git add "$VERSION_FILE" # Adiciona o arquivo de versão ao staging
else
    echo "AVISO: Arquivo de versão '$VERSION_FILE' não encontrado na raiz do projeto. Não foi possível atualizá-lo."
fi

mvn versions:set -DnewVersion="$RELEASE_VERSION" -DgenerateBackupPoms=false || { echo "Falha ao setar versão no POM. Abortando."; exit 1; }
git add pom.xml

git commit -m "Atualizacao de versao: $RELEASE_VERSION" || { echo "Falha ao commitar versão de release. Abortando."; exit 1; } # Mensagem de commit padrão

echo "-> Fazendo push da tag '$RELEASE_BRANCH'..."
git push origin "$RELEASE_BRANCH" || { echo "Falha ao fazer push da branch $RELEASE_BRANCH. Abortando."; exit 1; }

# 7. Criar a tag Git para a release
echo "-> Criando tag Git: $RELEASE_VERSION"
git tag "$RELEASE_VERSION" || { echo "Falha ao criar tag Git. Abortando."; exit 1; }

# --- PUSH DA TAG LOGO APÓS A CRIAÇÃO (apenas a tag recém-criada) ---
echo "-> Fazendo push da tag '$RELEASE_VERSION' para o repositório remoto..."
git push origin "$RELEASE_VERSION" || { echo "Falha ao fazer push da tag '$RELEASE_VERSION'. Abortando."; exit 1; }
echo "-> Push da tag '$RELEASE_VERSION' realizado com sucesso."

# 8. Executar o build do Maven para gerar o JAR e processar arquivos
echo "-> Executando build do Maven (clean package)..."
mvn clean package || { echo "Falha no build do Maven. Abortando."; exit 1; }

# 9. Mover o JAR gerado para uma pasta de "releases" e renomear (opcional)
if [ -f "target/projeto-automacao-release-${RELEASE_VERSION}-jar-with-dependencies.jar" ]; then
    echo "-> Movendo JAR para target/releases/..."
    mkdir -p target/releases
    mv "target/projeto-automacao-release-${RELEASE_VERSION}-jar-with-dependencies.jar" "target/releases/projeto-automacao-release-${RELEASE_VERSION}.jar"
else
    echo "AVISO: JAR não encontrado após o build. Verifique o pom.xml."
fi

echo "======================================================"
echo "    Processo de Release Concluído com Sucesso!        "
echo "        Versão Lançada: $RELEASE_VERSION              "
echo "======================================================"