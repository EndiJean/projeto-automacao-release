#!/bin/bash
set -e # Sai imediatamente se um comando retornar um status de saída diferente de zero

# --- Configurações ---
# Substitua com sua branch principal (ou 'master') e de desenvolvimento
RELEASE_BRANCH="release"
DEVELOP_BRANCH="desenvolvimento"

# Substitua com a URL do seu repositório Git
# Se estiver usando SSH (git@github.com...), certifique-se de que sua chave SSH está configurada no ambiente.
# Se usando HTTPS, e seu repo for privado, você precisará de um token de acesso pessoal (PAT).
# Ex: REPO_URL="https://seu-usuario:${GITHUB_TOKEN}@github.com/seu-usuario/projeto-automacao-release.git"
REPO_URL="https://github.com/EndiJean/projeto-automacao-release.git"

GIT_USER="EndiJean"
GIT_EMAIL="endijean91@gmail.com"

echo "======================================================"
echo "      Iniciando Processo de Release Automatizado      "
echo "======================================================"

# 1. Configurar usuário e e-mail do Git para os commits deste script
echo "-> Configurando usuário Git..."
git config user.name "$GIT_USER"
git config user.email "$GIT_EMAIL"

# 2. Garantir que o repositório está limpo antes de iniciar
if [[ $(git status --porcelain) ]]; then
    echo "ERRO: Seu diretório de trabalho não está limpo. Por favor, faça commit ou descarte as mudanças."
    exit 1
fi

# 3. Mover para a branch de desenvolvimento e atualizar
echo "-> Checkout para branch $DEVELOP_BRANCH e realizando pull..."
git checkout "$DEVELOP_BRANCH" || { echo "Falha ao mudar para a branch $DEVELOP_BRANCH"; exit 1; }
git pull origin "$DEVELOP_BRANCH" || { echo "Falha ao puxar da branch $DEVELOP_BRANCH"; exit 1; }

# 4. Obter a versão atual do projeto (e remover -SNAPSHOT)
CURRENT_POM_VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout | sed 's/-SNAPSHOT//')
if [[ -z "$CURRENT_POM_VERSION" ]]; then
    echo "ERRO: Não foi possível obter a versão atual do POM."
    exit 1
fi
echo "-> Versão atual do POM (sem SNAPSHOT): $CURRENT_POM_VERSION"

# Sugere a versão de release como a versão atual sem -SNAPSHOT
# e a próxima versão de desenvolvimento incrementando o número menor
RELEASE_VERSION="$CURRENT_POM_VERSION"
# Exemplo simples de incremento da última parte da versão (funciona para x.y.z)
IFS='.' read -r major minor patch <<< "$RELEASE_VERSION"
NEXT_MINOR=$((minor + 1))
NEXT_SNAPSHOT_VERSION="${major}.${NEXT_MINOR}.0-SNAPSHOT" # Assume que a próxima release será x.Y+1.0

# Confirmação manual (opcional, para testes manuais. Em CI/CD, remova ou defina por variáveis)
# read -p "Confirmar versão de release [$RELEASE_VERSION]: " user_release_version
# RELEASE_VERSION=${user_release_version:-$RELEASE_VERSION}
# read -p "Confirmar próxima versão de desenvolvimento [$NEXT_SNAPSHOT_VERSION]: " user_next_snapshot_version
# NEXT_SNAPSHOT_VERSION=${user_next_snapshot_version:-$NEXT_SNAPSHOT_VERSION}


echo "-> Versão de Release Definida: $RELEASE_VERSION"
echo "-> Próxima Versão de Desenvolvimento: $NEXT_SNAPSHOT_VERSION"

# 5. Fazer merge da branch de desenvolvimento para a branch de release
# echo "-> Fazendo merge de '$DEVELOP_BRANCH' para '$RELEASE_BRANCH'..."
# git checkout "$RELEASE_BRANCH" || { echo "Falha ao mudar para a branch $RELEASE_BRANCH"; exit 1; }
# git pull origin "$RELEASE_BRANCH" || { echo "Falha ao puxar da branch $RELEASE_BRANCH"; exit 1; }
# git merge --no-ff "$DEVELOP_BRANCH" -m "Merge $DEVELOP_BRANCH para Release $RELEASE_VERSION" || { echo "Falha ao fazer merge"; exit 1; }

# 6. Alterar a versão no pom.xml para a versão de release
echo "-> Atualizando pom.xml para a versão de release: $RELEASE_VERSION"
mvn versions:set -DnewVersion="$RELEASE_VERSION" -DgenerateBackupPoms=false || { echo "Falha ao setar versão no POM"; exit 1; }
git add pom.xml
git commit -m "Release: Versao $RELEASE_VERSION" || { echo "Falha ao commitar versão de release"; exit 1; }

# 7. Criar a tag Git para a release
echo "-> Criando tag Git: $RELEASE_VERSION"
git tag "$RELEASE_VERSION" || { echo "Falha ao criar tag Git"; exit 1; }

# 8. Executar o build do Maven para gerar o JAR e processar arquivos
echo "-> Executando build do Maven (clean package)..."
mvn clean package || { echo "Falha no build do Maven"; exit 1; }

# 9. Mover o JAR gerado para uma pasta de "releases" e renomear (opcional)
# O maven-assembly-plugin já gera um JAR com -jar-with-dependencies.jar
# Você pode renomeá-lo ou movê-lo se desejar uma organização específica.
if [ -f "target/projeto-automacao-release-${RELEASE_VERSION}-jar-with-dependencies.jar" ]; then
    echo "-> Movendo JAR para target/releases/..."
    mkdir -p target/releases
    mv "target/projeto-automacao-release-${RELEASE_VERSION}-jar-with-dependencies.jar" "target/releases/projeto-automacao-release-${RELEASE_VERSION}.jar"
else
    echo "AVISO: JAR não encontrado após o build. Verifique o pom.xml."
fi

# 10. Alterar a versão no pom.xml para a próxima versão de desenvolvimento (SNAPSHOT)
echo "-> Atualizando pom.xml para a próxima versão de desenvolvimento: $NEXT_SNAPSHOT_VERSION"
mvn versions:set -DnewVersion="$NEXT_SNAPSHOT_VERSION" -DgenerateBackupPoms=false || { echo "Falha ao setar próxima versão no POM"; exit 1; }
git add pom.xml
git commit -m "Bump version to $NEXT_SNAPSHOT_VERSION for next development iteration" || { echo "Falha ao commitar próxima versão"; exit 1; }

# 11. Fazer push de todas as mudanças (commits e tags) para a branch de release
echo "-> Fazendo push de commits e tags para '$RELEASE_BRANCH'..."
git push origin "$RELEASE_BRANCH" || { echo "Falha ao fazer push da branch $RELEASE_BRANCH"; exit 1; }
git push origin --tags || { echo "Falha ao fazer push das tags"; exit 1; }

# 12. Voltar para a branch de desenvolvimento e fazer merge da branch de release
echo "-> Checkout para '$DEVELOP_BRANCH' e realizando merge de '$RELEASE_BRANCH'..."
git checkout "$DEVELOP_BRANCH" || { echo "Falha ao mudar para a branch $DEVELOP_BRANCH"; exit 1; }
git pull origin "$DEVELOP_BRANCH" || { echo "Falha ao puxar da branch $DEVELOP_BRANCH"; exit 1; } # Puxa para garantir que não haverá conflitos no merge
git merge --no-ff "$RELEASE_BRANCH" -m "Merge Release $RELEASE_VERSION de volta para $DEVELOP_BRANCH" || { echo "Falha ao fazer merge de volta"; exit 1; }
git push origin "$DEVELOP_BRANCH" || { echo "Falha ao fazer push da branch $DEVELOP_BRANCH"; exit 1; }

echo "======================================================"
echo "    Processo de Release Concluído com Sucesso!        "
echo "        Versão Lançada: $RELEASE_VERSION              "
echo "======================================================"