#!/bin/bash
set -e # Sai imediatamente se um comando retornar um status de saída diferente de zero

SOURCE_BRANCH="desenvolvimento" # A branch da qual a branch de teste será criada

# Função para checar o status do Git e pausar se houver alterações
verifica_pendencias() {
    # Obtém o nome do próprio script para excluí-lo
    NOME_DO_PROPRIO_SCRIPT=$(basename "$0")

    PENDENCIAS_EXCETO_SCRIPT=$(git status --porcelain | grep -v "$NOME_DO_PROPRIO_SCRIPT" || true)

    if [[ -n "$PENDENCIAS_EXCETO_SCRIPT" ]]; then
        echo "--------------------------------------------------------"
        echo "ATENÇÃO: Existem alterações pendentes (modificações ou conflitos) no seu diretório de trabalho."
        echo "O script '$NOME_DO_PROPRIO_SCRIPT' foi ignorado nesta verificação."
        echo "Por favor, resolva os conflitos (se houver) e faça commit de TODAS as alterações."
        echo "Após resolver e commitar, pressione Enter para continuar..."
        echo "--------------------------------------------------------"
        read -r
        
        verifica_pendencias
    fi
}

# Função para executar um merge e lidar com conflitos (para merges na branch de teste)
fazer_merge_e_push_branch() {
    BRANCH_TO_MERGE_REMOTE="$1" # Branch remota a ser mesclada (ex: origin/feature/xyz)
    TARGET_BRANCH_LOCAL="$2" # Branch local onde o merge será feito (a branch de QA)

    echo "--------------------------------------------------------"
    echo "-> Tentando fazer merge de '$BRANCH_TO_MERGE_REMOTE' para '$TARGET_BRANCH_LOCAL'..."
    if git merge --no-ff "$BRANCH_TO_MERGE_REMOTE" -m "Merge branch '$BRANCH_TO_MERGE_REMOTE' into $TARGET_BRANCH_LOCAL for QA"; then
        echo "Merge de '$BRANCH_TO_MERGE_REMOTE' realizado com sucesso."
    else
        echo "--------------------------------------------------------"
        echo "CONFLITO DE MERGE DETECTADO ao mesclar '$BRANCH_TO_MERGE_REMOTE' em '$TARGET_BRANCH_LOCAL'."
        echo "Por favor, resolva os conflitos manualmente e faça um commit de merge."
        echo "Comandos úteis: git status, git diff, git add, git commit -m 'Merge de $BRANCH_TO_MERGE_REMOTE resolvido'."
        echo "Após resolver o conflito e commitar, pressione Enter para continuar..."
        echo "--------------------------------------------------------"
        read -r
        verifica_pendencias
        echo "Conflito de '$BRANCH_TO_MERGE_REMOTE' resolvido e commited."
    fi

    echo "-> Fazendo push das alterações de merge para '$TARGET_BRANCH_LOCAL'..."
    git push origin "$TARGET_BRANCH_LOCAL" || { echo "Falha ao fazer push da branch $TARGET_BRANCH_LOCAL após merge de $BRANCH_TO_MERGE_REMOTE. Abortando."; exit 1; }
    echo "Push do merge de '$BRANCH_TO_MERGE_REMOTE' realizado com sucesso."
}

echo "======================================================"
echo "       Iniciando Gerenciador de Branches de QA        "
echo "======================================================"

# Verificar se o diretório existe e é um repositório Git
read -p "Informe o caminho do diretório do repositório Git: " REPO_DIR

if [ ! -d "$REPO_DIR" ]; then
    echo "ERRO: O diretório '$REPO_DIR' não existe."
    exit 1
fi

# Testa se é um repositório Git. A opção -C faz o comando ser executado no diretório especificado.
if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERRO: O diretório '$REPO_DIR' não é um repositório Git válido."
    exit 1
fi

cd "$REPO_DIR" || { echo "Erro ao acessar o diretório $REPO_DIR"; exit 1; }

# 1. Garante que o repositório está limpo antes de iniciar
echo "-> Verificando status inicial do Git..."
verifica_pendencias

# 2. Solicitar o nome da branch de QA desejada
echo "--------------------------------------------------------"
read -p "Informe o NOME da branch de QA: " QA_BRANCH_NAME
if [ -z "$QA_BRANCH_NAME" ]; then
    echo "ERRO: Nome da branch de QA não pode ser vazio. Finalizando."
    exit 1
fi

# 3. Verificar se a branch de QA já existe (localmente ou remotamente)
BRANCH_EXISTS=false
if git show-ref --verify --quiet "refs/heads/$QA_BRANCH_NAME"; then
    BRANCH_EXISTS=true
    echo "-> Branch local '$QA_BRANCH_NAME' já existe."
elif git show-ref --verify --quiet "refs/remotes/origin/$QA_BRANCH_NAME"; then
    BRANCH_EXISTS=true
    echo "-> Branch remota 'origin/$QA_BRANCH_NAME' já existe."
fi

# 4. Ação baseada na existência da branch
if [ "$BRANCH_EXISTS" = true ]; then
    echo "-> A branch '$QA_BRANCH_NAME' já existe. Usando a branch existente."
    git checkout "$QA_BRANCH_NAME" || { echo "Falha ao mudar para a branch '$QA_BRANCH_NAME'. Abortando."; exit 1; }
    echo "-> Realizando pull para garantir que '$QA_BRANCH_NAME' esteja atualizada..."
    git pull origin "$QA_BRANCH_NAME" || { echo "Falha ao puxar da branch '$QA_BRANCH_NAME'. Abortando."; exit 1; }
else
    echo "-> A branch '$QA_BRANCH_NAME' NÃO existe. Criando nova branch a partir de '$SOURCE_BRANCH'..."
    git checkout "$SOURCE_BRANCH" || { echo "Falha ao mudar para a branch '$SOURCE_BRANCH'. Abortando."; exit 1; }
    echo "-> Realizando pull da '$SOURCE_BRANCH' para garantir que esteja atualizada antes de criar a nova branch..."
    git pull origin "$SOURCE_BRANCH" || { echo "Falha ao puxar da branch '$SOURCE_BRANCH'. Abortando."; exit 1; }
    git checkout -b "$QA_BRANCH_NAME" || { echo "Falha ao criar a branch '$QA_BRANCH_NAME'. Abortando."; exit 1; }
    echo "-> Nova branch '$QA_BRANCH_NAME' criada e checkout realizado."
    echo "-> Fazendo push da nova branch '$QA_BRANCH_NAME' para o repositório remoto..."
    git push -u origin "$QA_BRANCH_NAME" || { echo "Falha ao fazer push inicial da branch '$QA_BRANCH_NAME'. Abortando."; exit 1; }
fi

echo "-> Atualizando referências de branches remotas (git fetch origin)..."
git fetch origin || { echo "Falha ao buscar branches remotas. Verifique a conexão e permissões."; exit 1; }

# 5. Loop para informar as branches a serem mescladas na branch de QA
MERGE_BRANCHES_REMOTE=()
echo "--------------------------------------------------------"
echo "Agora, informe as branches para fazer merge na branch de QA ('$QA_BRANCH_NAME')."
while true; do
    echo "--------------------------------------------------------"
    read -p "Informe o NOME da branch remota para fazer merge na '$QA_BRANCH_NAME' (ou deixe em branco para finalizar): " BRANCH_INPUT_NAME
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
    echo "Nenhuma branch informada para merge. Finalizando o processo de QA."
else
    echo "--------------------------------------------------------"
    echo "As seguintes branches REMOTAS serão mescladas uma a uma na '$QA_BRANCH_NAME':"
    for branch in "${MERGE_BRANCHES_REMOTE[@]}"; do
        echo "  - $branch"
    done
    echo "--------------------------------------------------------"

    # 6. Executar merges sequencialmente com push após cada um
    echo "-> Iniciando processo de merge e push de cada branch remota informada..."
    for branch_to_merge_remote in "${MERGE_BRANCHES_REMOTE[@]}"; do
        fazer_merge_e_push_branch "$branch_to_merge_remote" "$QA_BRANCH_NAME"
        echo "--------------------------------------------------------"
        read -p "Merge e push de '$branch_to_merge_remote' concluído. Pressione Enter para continuar para a próxima branch (se houver)..."
        echo "--------------------------------------------------------"
    done

    echo "Todos os merges solicitados foram concluídos e enviados para o repositório remoto."
fi


echo "======================================================"
echo "    Gerenciamento de Branch de QA Concluído!          "
echo "     Branch de QA Trabalhada: $QA_BRANCH_NAME         "
echo "======================================================"