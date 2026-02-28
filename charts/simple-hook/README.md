# simple-hook

A Helm chart to run a single [Helm hook](https://helm.sh/docs/topics/charts_hooks/) as a Job.

## Usage

```bash
helm install my-hook oci://ghcr.io/evil8io/charts/simple-hook
```

## Example

Wait for a CRD to be available before installing a release:

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

See [values.yaml](values.yaml) for all configurable values.
