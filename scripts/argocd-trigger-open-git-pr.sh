#!/bin/bash
# argocd-trigger-open-git-pr.sh
#
# Mesma logica do script de HMG, mas em vez de push direto na master, cria
# uma branch deploy/<app>-<version>-<sha> e abre PR para master no repo IaC
# de PRD. PR fica aguardando review da equipe Minu.
#
# Variaveis adicionais:
#   MTCLI_GITHUB_API_TOKEN  token com permissao para abrir PR no repo IaC
#   LAST_COMMIT_SHA         hash do commit que disparou a pipeline
#
set -euo pipefail

# =============================================================================
# 1. Versao
# =============================================================================
if [ ! -f "./metadata.json" ]; then
  echo "ERRO: metadata.json nao encontrado na raiz do projeto."
  exit 1
fi
IMAGE_VERSION=$(jq -r '.version' metadata.json)

VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'
SOURCE_BRANCH=${GITHUB_REF_NAME:-}

if [[ "$SOURCE_BRANCH" == "master" || "$SOURCE_BRANCH" == "main" ]]; then
  if ! [[ "$IMAGE_VERSION" =~ $VERSION_REGEX ]]; then
    echo "ERRO: versao '$IMAGE_VERSION' fora do padrao MAJOR.MINOR.PATCH em $SOURCE_BRANCH."
    exit 1
  fi
fi

CO_AUTHOR=$(git log -1 --pretty=format:'%cn <%ce>')
ORIGINAL_COMMIT=$(git log -1 --pretty='%H - %s')

# =============================================================================
# 2. Resolucao de paths
# =============================================================================
BASE_PATH="/gitops"
ENVIRONMENT="${ENVIRONMENT:-prd}"
MICROSERVICE="${MICROSERVICE:-metadata.${ENVIRONMENT}}"
TOOLKIT_DIR="$BASE_PATH/engine-deploy-toolkit"

case "$ENVIRONMENT" in
  hmg|prd) IAC_REPO_NAME="iac-engine-pix-k8s-${ENVIRONMENT}" ;;
  *) echo "ERRO: ENVIRONMENT invalido: $ENVIRONMENT"; exit 1 ;;
esac
IAC_REPO_PATH="$BASE_PATH/$IAC_REPO_NAME"

if [ ! -f "./deploy/${MICROSERVICE}.json" ]; then
  echo "ERRO: ./deploy/${MICROSERVICE}.json nao encontrado."
  exit 1
fi
APP_NAME=$(jq -r '.app_name' "./deploy/${MICROSERVICE}.json")

PATH_VARS="$IAC_REPO_PATH/$APP_NAME/metadata.json"
if [ ! -f "$PATH_VARS" ]; then
  echo "ERRO: $PATH_VARS nao encontrado."
  exit 1
fi

# =============================================================================
# 3. Render
# =============================================================================
rm -rf "$BASE_PATH/manifests"
mkdir -p "$BASE_PATH/manifests"

cp -v "$TOOLKIT_DIR/templates/$ENVIRONMENT/"*.yml "$BASE_PATH/manifests/"

if [ -d "$IAC_REPO_PATH/$APP_NAME/kustomization" ]; then
  cp -v "$IAC_REPO_PATH/$APP_NAME/kustomization/"*.yml "$BASE_PATH/manifests/"
fi

ISTIODEPLOY="${ISTIODEPLOY:-false}"
ISTIODEPLOYDOUBLE="${ISTIODEPLOYDOUBLE:-false}"
ISTIO=""
if [[ "$ISTIODEPLOY" == "false" && "$ISTIODEPLOYDOUBLE" == "false" ]]; then
  cp "$BASE_PATH/manifests/kustomization-no-istio.yml" "$BASE_PATH/manifests/kustomization.yml"
elif [ "$ISTIODEPLOYDOUBLE" == "true" ]; then
  ISTIO="istio-double"
elif [ "$ISTIODEPLOY" == "true" ]; then
  ISTIO="istio"
fi
rm -f "$BASE_PATH/manifests/kustomization-no-istio.yml"

extract_var() {
  jq -r --arg k "$1" '.[$k] // ""' "$PATH_VARS"
}

declare -A VARS=(
  [APP_NAME]="app_name"
  [CLUSTER_NAME]="cluster_name"
  [NAMESPACE]="namespace"
  [HEALTHCHECK_LIVE]="healthcheck_liveness_route"
  [HEALTHCHECK_READY]="healthcheck_readness_route"
  [LIMITS_CPU]="limits_cpu"
  [LIMITS_MEMORY]="limits_memory"
  [HPA_MIN]="hpa_min"
  [HPA_MAX]="hpa_max"
  [REPLICAS]="replicas"
  [PORT]="port"
  [ISTIO_FULL_URL]="istio_full_url"
  [ISTIO_GATEWAY]="istio_gateway"
  [ISTIO_INTERNAL_URL]="istio_internal_url"
  [INTERNAL_ISTIO_GATEWAY]="internal_istio_gateway"
)
for key in "${!VARS[@]}"; do
  export "$key"=$(extract_var "${VARS[$key]}")
done

if ! grep -q '"topic_' "$PATH_VARS"; then
  if [ ! -f "$IAC_REPO_PATH/$APP_NAME/kustomization/awssm.yml" ]; then
    sed -i '38,88d' "$BASE_PATH/manifests/awssm.yml"
  fi
fi

declare -A SUBSTITUTIONS=(
  [_APP_NAME_]="$APP_NAME"
  [_CLUSTER_NAME_]="$CLUSTER_NAME"
  [_NAMESPACE_]="$NAMESPACE"
  [_HEALTHCHECKLIVE_]="$HEALTHCHECK_LIVE"
  [_HEALTHCHECKREADY_]="$HEALTHCHECK_READY"
  [_LIMITS_CPU_]="$LIMITS_CPU"
  [_LIMITS_MEMORY_]="$LIMITS_MEMORY"
  [_HPA_MIN_]="$HPA_MIN"
  [_HPA_MAX_]="$HPA_MAX"
  [_PORT_]="$PORT"
  [_IMAGE_VERSION_]="$IMAGE_VERSION"
  [_ISTIO_FULL_URL_]="$ISTIO_FULL_URL"
)
for k in "${!SUBSTITUTIONS[@]}"; do
  find "$BASE_PATH/manifests" -type f -name "*.yml" -exec sed -i "s|$k|${SUBSTITUTIONS[$k]}|g" {} +
done

KUSTOMIZATION_FILE="$BASE_PATH/manifests/kustomization.yml"
ISTIO_FILE="$BASE_PATH/manifests/istio.yml"
ISTIO_DOUBLE_FILE="$BASE_PATH/manifests/istio-double.yml"

if [[ "$ISTIODEPLOY" == "false" && -f "$ISTIO_FILE" ]]; then
  rm -f "$ISTIO_FILE"
elif [ -n "$ISTIO" ] && [ -f "$ISTIO_FILE" ]; then
  sed -i "s/_ISTIO_/$ISTIO/g" "$KUSTOMIZATION_FILE"
  sed -i "s/_ISTIO_GATEWAY_/$ISTIO_GATEWAY/g" "$ISTIO_FILE"
fi

if [[ "$ISTIODEPLOYDOUBLE" == "false" && -f "$ISTIO_DOUBLE_FILE" ]]; then
  rm -f "$ISTIO_DOUBLE_FILE"
elif [ "$ISTIODEPLOYDOUBLE" == "true" ] && [ -f "$ISTIO_DOUBLE_FILE" ]; then
  sed -i "s/_ISTIO_/$ISTIO/g" "$KUSTOMIZATION_FILE"
  sed -i "s/_ISTIO_INTERNAL_URL_/$ISTIO_INTERNAL_URL/g" "$ISTIO_DOUBLE_FILE"
  sed -i "s/_INTERNAL_ISTIO_GATEWAY_/$INTERNAL_ISTIO_GATEWAY/g" "$ISTIO_DOUBLE_FILE"
  sed -i "s/_ISTIO_GATEWAY_/$ISTIO_GATEWAY/g" "$ISTIO_DOUBLE_FILE"
fi

NODE_GROUPS=$(extract_var "node_groups")
if [ -n "$NODE_GROUPS" ]; then
  sed -i "s/_NODE_GROUPS_/$NODE_GROUPS/g" "$BASE_PATH/manifests/deployment.yml"
else
  sed -i '/_NODE_GROUPS_/d' "$BASE_PATH/manifests/deployment.yml"
fi

IMAGE_NAME_OVERRIDE=$(extract_var "image_name")
IMAGE_NAME="${IMAGE_NAME_OVERRIDE:-$APP_NAME}"
sed -i "s/_IMAGE_NAME_/$IMAGE_NAME/g" "$BASE_PATH/manifests/deployment.yml"

REQUESTS_CPU=$(extract_var "requests_cpu")
sed -i "s/_REQUESTS_CPU_/${REQUESTS_CPU:-50m}/g" "$BASE_PATH/manifests/deployment.yml"

REQUESTS_MEMORY=$(extract_var "requests_memory")
sed -i "s/_REQUESTS_MEMORY_/${REQUESTS_MEMORY:-128Mi}/g" "$BASE_PATH/manifests/deployment.yml"

# =============================================================================
# 4. Branch + commit + PR (PRD: sem autonomia, exige aprovacao Minu)
# =============================================================================
GIT_BRANCH="deploy/${APP_NAME}-${IMAGE_VERSION}-${LAST_COMMIT_SHA:-manual}"

cd "$IAC_REPO_PATH"
git config --global user.email "ci-bot@users.noreply.github.com"
git config --global user.name  "epix-cnab-ci"
git checkout -B "$GIT_BRANCH"

mkdir -p "$APP_NAME"
cp "$BASE_PATH/manifests/"*.yml "$APP_NAME/"

git add .
if git diff --cached --quiet; then
  echo "Nada mudou nos manifests PRD — nao abriremos PR."
  exit 0
fi
git commit -m "$APP_NAME - $IMAGE_VERSION: Manifests files updated

Source commit: $ORIGINAL_COMMIT

Co-authored-by: $CO_AUTHOR"
git push -u origin "$GIT_BRANCH"

# Abre PR via API REST do GitHub (sem dependencia do gh CLI)
PR_BODY="Atualizacao automatica da tag de imagem para PRD.

Branch: ${GIT_BRANCH}
Source commit: ${ORIGINAL_COMMIT}

ATENCAO: este PR exige aprovacao da equipe Minu antes do merge."

curl -sSf -X POST \
  -H "Authorization: token ${MTCLI_GITHUB_API_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/Minutrade/${IAC_REPO_NAME}/pulls" \
  -d "$(jq -n \
        --arg title "${APP_NAME} - ${IMAGE_VERSION} - Manifests update" \
        --arg head  "${GIT_BRANCH}" \
        --arg base  "master" \
        --arg body  "${PR_BODY}" \
        '{title:$title, head:$head, base:$base, body:$body}')"
