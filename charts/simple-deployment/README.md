# simple-deployment

> **Note:** This chart is automatically synced from a private repository. Do not edit it here directly.

A Helm chart to deploy a Deployment that runs a simple script without end.

## Usage

```bash
helm install my-deployment oci://ghcr.io/evil8io/charts/simple-deployment
```

## Example

Log the number of pods in the release namespace every minute:

```yaml
image: dtzar/helm-kubectl:latest

script: |
  while true; do
    kubectl get pods --namespace "$NAMESPACE" --no-headers | wc -l
    sleep 60
  done

rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods"]
      verbs: ["list"]
```

See [values.yaml](values.yaml) for all configurable values.
