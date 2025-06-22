set -e

CAMINHO_PASTA_LIB="$HOME/lib" # Caminho da pasta de destino no diretório do usuário
SCRIPT_GERADOR_HASH="gerarHash.jar" # Nome do arquivo JAR a ser executado na pasta 'lib'

# --- 1. Solicita e Valida o Diretório do Projeto Maven ---
read -p "Informe o caminho do diretório do projeto (onde está o pom.xml): " DIRETORIO_DO_PROJETO

DIRETORIO_DO_PROJETO="${DIRETORIO_DO_PROJETO//\\//}"

if [ -z "$DIRETORIO_DO_PROJETO" ]; then
    echo "ERRO: O caminho do diretório do projeto não pode ser vazio."
    exit 1
fi

if [ ! -d "$DIRETORIO_DO_PROJETO" ]; then
    echo "ERRO: O diretório '$DIRETORIO_DO_PROJETO' não existe."
    exit 1
fi

if [ ! -f "$DIRETORIO_DO_PROJETO/pom.xml" ]; then
    echo "ERRO: Não foi encontrado um pom.xml em '$DIRETORIO_DO_PROJETO'."
    exit 1
fi

if ! git -C "$DIRETORIO_DO_PROJETO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERRO: O diretório '$DIRETORIO_DO_PROJETO' não é um repositório Git válido."
    exit 1
fi

cd "$REPO_DIR" || { echo "Erro ao acessar o diretório $REPO_DIR"; exit 1; }

CAMINHO_COMPLETO_TARGET="$DIRETORIO_DO_PROJETO/target"

echo "======================================================"
echo "         Iniciando o Processo de Geração de Lib       "
echo "======================================================"
echo "-> Diretório do Projeto Maven: '$DIRETORIO_DO_PROJETO'"

# --- 2. Executar o Build do Maven com o Profile 'standalonelib' ---
echo "-> Executando build do Maven com o perfil 'standalonelib'..."
(cd "$DIRETORIO_DO_PROJETO" && mvn clean package -P standalonelib) || {
    echo "Falha no build do Maven. Abortando."; 
    exit 1; 
}
echo "-> Build do Maven concluído com sucesso."

# --- 3.Verificar se a pasta 'target' existe no diretório do script ---
echo "-> Procurando a pasta '$CAMINHO_COMPLETO_TARGET'..."
if [ ! -d "$CAMINHO_COMPLETO_TARGET" ]; then
    echo "ERRO: Pasta '$CAMINHO_COMPLETO_TARGET' não encontrada."
    echo "Certifique-se de que o script está sendo executado na raiz de um projeto Maven/Gradle."
    exit 1
fi
echo "-> Pasta '$CAMINHO_COMPLETO_TARGET' encontrada."

# --- 4. Obter informações do JAR a partir do pom.xml ---
echo "-> Lendo informações do pom.xml para determinar o nome do JAR..."

# Usamos o Maven para extrair dados do pom.xml que está no mesmo diretório do script.
ID_DO_ARTEFATO=$(mvn -f "$DIRETORIO_DO_PROJETO_MAVEN/pom.xml" help:evaluate -Dexpression=project.artifactId -q -DforceStdout 2>/dev/null)
VERSAO_DO_PROJETO=$(mvn -f "$DIRETORIO_DO_PROJETO_MAVEN/pom.xml" help:evaluate -Dexpression=project.version -q -DforceStdout 2>/dev/null)
EMPACOTAMENTO_DO_PROJETO=$(mvn -f "$DIRETORIO_DO_PROJETO/pom.xml" help:evaluate -Dexpression=project.packaging -q -DforceStdout 2>/dev/null)
NOME_FINAL_DO_BUILD=$(mvn -f "$DIRETORIO_DO_PROJETO_MAVEN/pom.xml" help:evaluate -Dexpression=project.build.finalName -q -DforceStdout 2>/dev/null)

if [[ -n "$NOME_FINAL_DO_BUILD" && "$NOME_FINAL_DO_BUILD" != "\${project.artifactId}-\${project.version}" && "$NOME_FINAL_DO_BUILD" != "\${project.version}" ]]; then
    BASE_NOME_JAR="$NOME_FINAL_DO_BUILD"
    echo "-> Usando '<finalName>' do pom.xml como base do nome: $BASE_NOME_JAR"
else
    BASE_NOME_JAR="${ID_DO_ARTEFATO}-${VERSAO_DO_PROJETO}"
    echo "-> Usando nome padrão (artifactId-version) como base do nome (finalName não especificado ou é placeholder): $BASE_NOME_JAR"
fi

# Procura o arquivo JAR na pasta 'target' usando o nome base e a extensão de empacotamento.
CAMINHO_JAR_ORIGEM=$(find "$CAMINHO_COMPLETO_TARGET" -maxdepth 1 -name "${BASE_NOME_JAR}*${EMPACOTAMENTO_DO_PROJETO}" | head -n 1)

# 5. Validar a existência do arquivo JAR encontrado
echo "-> Verificando a existência do arquivo JAR: '$CAMINHO_JAR_ORIGEM'..."
if [ ! -f "$CAMINHO_JAR_ORIGEM" ]; then
    echo "ERRO: Arquivo JAR '$CAMINHO_JAR_ORIGEM' não encontrado. Abortando o processo."
    echo "Certifique-se de que o build do projeto foi executado e o JAR foi gerado corretamente."
    exit 1
fi
NOME_ORIGINAL_DO_JAR=$(basename "$CAMINHO_JAR_ORIGEM")
echo "-> Arquivo JAR '$NOME_ORIGINAL_DO_JAR' encontrado e pronto para cópia."

# 6. Criar a pasta 'lib' no diretório do usuário, se não existir
echo "-> Verificando/Criando a pasta '$CAMINHO_PASTA_LIB' no diretório do usuário..."
mkdir -p "$CAMINHO_PASTA_LIB" || { echo "Falha ao criar a pasta '$CAMINHO_PASTA_LIB'. Verifique as permissões de acesso."; exit 1; }
echo "-> Pasta '$CAMINHO_PASTA_LIB' está pronta."

# --- 7. Copiar o JAR para a pasta 'lib' e renomear opcionalmente ---
NOME_FINAL_JAR_DESTINO="" # Variável que armazenará o nome final escolhido para o JAR copiado

echo "--------------------------------------------------------"
# Loop para garantir que um nome válido seja escolhido (seja o original ou um novo nome)
while true; do
    read -p "Deseja renomear o arquivo JAR ao copiar para '$CAMINHO_PASTA_LIB'? (Nome atual: $NOME_ORIGINAL_DO_JAR) (s/N): " ESCOLHA_RENOMEAR
    ESCOLHA_RENOMEAR=${ESCOLHA_RENOMEAR:-n}

    NOME_BASE_PARA_VALIDACAO=""

    if [[ "$ESCOLHA_RENOMEAR" =~ ^[Ss]$ ]]; then
        read -p "Informe o NOVO nome para o arquivo JAR (sem extensão .jar): " NOME_PERSONALIZADO_BASE
        if [ -z "$NOME_PERSONALIZADO_BASE" ]; then
            echo "AVISO: O nome personalizado não pode ser vazio. Por favor, tente novamente ou escolha não renomear."
            continue
        fi
        NOME_BASE_PARA_VALIDACAO="$NOME_PERSONALIZADO_BASE"
        NOME_FINAL_JAR_DESTINO="${NOME_PERSONALIZADO_BASE}.jar"
    else
        NOME_BASE_PARA_VALIDACAO=$(basename "$NOME_ORIGINAL_DO_JAR" .jar)
        NOME_FINAL_JAR_DESTINO="$NOME_ORIGINAL_DO_JAR"
        echo "-> Você optou por manter o nome original: '$NOME_ORIGINAL_DO_JAR'."
    fi

    PASTA_A_VERIFICAR="${CAMINHO_PASTA_LIB}/${NOME_BASE_PARA_VALIDACAO}"
    if [ -d "$PASTA_A_VERIFICAR" ]; then
        echo "ERRO: Já existe uma pasta com o nome '$NOME_BASE_PARA_VALIDACAO' em '$CAMINHO_PASTA_LIB'."
        echo "Por favor, escolha um nome diferente ou remova a pasta existente para prosseguir."
        
        if [[ "$ESCOLHA_RENOMEAR" =~ ^[Nn]$ ]]; then
            read -p "A pasta '$NOME_BASE_PARA_VALIDACAO' já existe. Deseja tentar renomear o JAR agora? (s/N): " FORCAR_RENOMEAR
            FORCAR_RENOMEAR=${FORCAR_RENOMEAR:-n}
            if [[ "$FORCAR_RENOMEAR" =~ ^[Ss]$ ]]; then
                echo "-> Ok, voltando para a opção de renomear o JAR..."
                continue
            else
                echo "Processo abortado devido a conflito de nome de pasta para o JAR."
                exit 1
            fi
        else
            continue
        fi
    else
        break
    fi
done

CAMINHO_JAR_DESTINO="$CAMINHO_PASTA_LIB/$NOME_FINAL_JAR_DESTINO"

echo "-> Copiando '$CAMINHO_JAR_ORIGEM' para '$CAMINHO_JAR_DESTINO'..."
cp "$CAMINHO_JAR_ORIGEM" "$CAMINHO_JAR_DESTINO" || { echo "Falha ao copiar o arquivo JAR. Verifique as permissões."; exit 1; }
echo "-> Arquivo copiado com sucesso. Nome de destino: '$NOME_FINAL_JAR_DESTINO' em '$CAMINHO_PASTA_LIB'."

# --- 7. Executar o arquivo 'gerarHash.jar' na pasta 'lib' ---
CAMINHO_COMPLETO_SCRIPT_HASH="$CAMINHO_PASTA_LIB/$SCRIPT_GERADOR_HASH"
echo "-> Verificando e executando o arquivo '$SCRIPT_GERADOR_HASH' em '$CAMINHO_PASTA_LIB'..."

if [ ! -f "$CAMINHO_COMPLETO_SCRIPT_HASH" ]; then
    echo "ERRO: Arquivo '$SCRIPT_GERADOR_HASH' não encontrado em '$CAMINHO_PASTA_LIB'."
    echo "Certifique-se de que o arquivo 'gerarHash.jar' está presente na pasta '$CAMINHO_PASTA_LIB'."
    exit 1
fi

java -jar "$CAMINHO_COMPLETO_SCRIPT_HASH" || { echo "Falha ao executar '$SCRIPT_GERADOR_HASH'."; exit 1; }
echo "-> Arquivo '$SCRIPT_GERADOR_HASH' executado com sucesso."

echo "======================================================"
echo "     Processo de Geração de Lib Concluído com Sucesso!"
echo "======================================================"