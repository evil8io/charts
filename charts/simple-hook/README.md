# simple-hook

Runs a script as a Job in a [Helm hook](https://helm.sh/docs/topics/charts_hooks/).

## Example

Wait for a CRD before the install of the release:

```yaml
image: dtzar/helm-kubectl:latest

hook:
  type: pre-install
  deletePolicy: before-hook-creation,hook-succeeded

script: |
  kubectl wait crd certificates.cert-manager.io \
    --for=condition=Established \
    --timeout=120s

rbac:
  create: true
  scope: cluster
  rules:
    - apiGroups: ["apiextensions.k8s.io"]
      resources: ["customresourcedefinitions"]
      verbs: ["get", "list", "watch"]
```
