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
    │   ├── deployment-mtls.yml      # variante com porta 8443 + Service mtls (opt-in)
    │   ├── istio.yml                # VirtualService + Gateway
    │   ├── istio-mtls.yml           # variante com listener TLS passthrough (opt-in)
    │   ├── istio-double.yml         # VirtualService duplo (publico + interno)
    │   ├── kustomization.yml        # com Istio
    │   └── kustomization-no-istio.yml
    └── prd/
        └── ... (mesmo set, valores ajustados para PRD)
```

## mTLS (opt-in por app)

Alguns apps expõem um endpoint `/api/v2` autenticado por certificado de
cliente (mTLS) numa porta Tomcat dedicada (8443), além do HTTP normal na
`_PORT_`. Isso **não é o padrão** — só é ativado quando o app pede
explicitamente, para não afetar os demais projetos que usam este toolkit.

Para habilitar, adicione no `metadata.json` do app (dentro do repo
`iac-engine-pix-k8s-<env>/<app_name>/metadata.json`):

```json
{
  "mtls_enabled": true,
  "mtls_tls_port": 9443,
  "mtls_gateway_secondary": "k8s-hmg-internal-gateway-2"
}
```

- `mtls_enabled` — se `true`, o script troca `deployment.yml`/`istio.yml`
  pelas variantes `deployment-mtls.yml`/`istio-mtls.yml` antes de renderizar.
  Padrão `false` (nenhuma mudança de comportamento para quem não define).
- `mtls_tls_port` — porta do listener `PASSTHROUGH` no Gateway da infra
  (usada no `tls.match.port` do VirtualService).
- `mtls_gateway_secondary` — Gateway resource (namespace `default`) que
  carrega esse listener, adicionado à lista de `gateways` do VirtualService
  junto com o `istio_gateway` já existente.

A variante `deployment-mtls.yml` adiciona a porta de container 8443, a
annotation `traffic.sidecar.istio.io/excludeInboundPorts: "8443"` e a porta
`mtls` no Service. A variante `istio-mtls.yml` adiciona o bloco `tls` de
passthrough e bloqueia `/api/v2` em HTTP puro (retorna 421). Jobs não podem
habilitar mTLS (não expõem porta de serviço).

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
