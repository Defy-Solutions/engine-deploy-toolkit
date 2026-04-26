# engine-deploy-toolkit (versao Java/Maven)

Esta pasta contem a versao **adaptada para Java/Maven** dos scripts e templates
que originalmente foram fornecidos pela Minu como exemplo Node/Python. A
adaptacao mantem a logica de render de manifests (templates + substituicao
de variaveis), mas:

- Le versao do projeto a partir de `metadata.json` (Maven), nao mais de
  `package.json` (Node) ou `pyproject.toml` (Python).
- Usa `jq` em vez de `node -p -e "require(...)"` para extrair valores.
- Usa o nome correto `engine-deploy-toolkit` (nao `minutrade-deploy-toolkit`).
- Usa o nome correto `iac-engine-pix-k8s-{hmg,prd}` (nao `k8s-manifests-{env}`).
- Sem dependencia de Node ou Python no runner.

## Como sincronizar com o repositorio autoritativo

O conteudo desta pasta deve viver em
[`https://github.com/Defy-Solutions/engine-deploy-toolkit`](https://github.com/Defy-Solutions/engine-deploy-toolkit).
A pipeline da aplicacao **clona aquele repo** durante o deploy.

Sequencia de setup inicial (uma unica vez):

```bash
# Em alguma pasta fora deste repo:
git clone https://github.com/Defy-Solutions/engine-deploy-toolkit.git
cd engine-deploy-toolkit

# Copia os scripts e templates desta pasta:
cp -r /caminho/para/epix-envia-ordem-pix-cnab/infra/engine-deploy-toolkit/scripts ./
cp -r /caminho/para/epix-envia-ordem-pix-cnab/infra/engine-deploy-toolkit/templates ./
chmod +x scripts/*.sh

git add .
git commit -m "Adapta toolkit para Java/Maven"
git push origin master
```

Depois desse setup, **a pasta `infra/engine-deploy-toolkit/` no repo da aplicacao
serve apenas como referencia**. Voce pode mante-la versionada (recomendado, para
auditoria) ou apaga-la apos o setup. Atualizacoes futuras devem ser feitas
direto no repo `Defy-Solutions/engine-deploy-toolkit`.

## Templates

A pasta `templates/` espelha o que a Minu enviou. Mantive como esta — os
templates sao agnosticos a linguagem (apenas YAML K8s com placeholders
`_APP_NAME_`, `_IMAGE_VERSION_` etc.).

## Estrutura

```
engine-deploy-toolkit/
├── scripts/
│   ├── argocd-trigger-open-push-on-branch.sh   # HMG: push direto
│   └── argocd-trigger-open-git-pr.sh           # PRD: abre PR
└── templates/
    ├── hmg/
    │   ├── awssm.yml                # ExternalSecret (AWS Secrets Manager)
    │   ├── deployment.yml           # Deployment + KEDA ScaledObject + Service
    │   ├── istio.yml                # VirtualService + Gateway
    │   ├── istio-double.yml         # VirtualService duplo (publico + interno)
    │   ├── kustomization.yml        # com Istio
    │   └── kustomization-no-istio.yml
    └── prd/
        └── ... (mesmo set, valores ajustados para PRD)
```

## Variaveis esperadas pelos scripts

Definidas no workflow do GitHub Actions:

| Variavel              | Descricao                                                           |
|-----------------------|---------------------------------------------------------------------|
| `ENVIRONMENT`         | `hmg` ou `prd`                                                      |
| `MICROSERVICE`        | basename do JSON em `./deploy/` (e.g. `metadata.hmg`) ou nome da app se nao houver arquivo local |
| `APP_NAME`            | nome da app; opcional quando `MICROSERVICE` ja for o nome da app    |
| `GIT_BRANCH`          | branch destino no repo IaC (default `master`)                       |
| `ISTIODEPLOY`         | `true` para incluir manifest Istio simples                          |
| `ISTIODEPLOYDOUBLE`   | `true` para Istio publico + interno                                 |
| `MTCLI_GITHUB_API_TOKEN` | token usado pelo PR script (PRD)                                  |
| `LAST_COMMIT_SHA`     | hash do commit; entra no nome da branch de PR                       |

Os scripts primeiro tentam ler `./deploy/${MICROSERVICE}.json`. Se o arquivo
nao existir, usam `APP_NAME`; se `APP_NAME` nao existir e `MICROSERVICE` nao
comecar com `metadata.`, usam `MICROSERVICE` como nome da aplicacao.
