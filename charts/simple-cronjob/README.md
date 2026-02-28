# simple-cronjob

A Helm chart to deploy a CronJob that runs a simple script on a schedule.

## Usage

```bash
helm install my-cronjob oci://ghcr.io/evil8io/charts/simple-cronjob
```

## Example

Clean up completed jobs older than 1 hour:

```yaml
image: dtzar/helm-kubectl:latest

schedule: "0 * * * *"

script: |
  kubectl delete jobs \
    --field-selector status.successful=1 \
    --namespace "$NAMESPACE"

rbac:
  create: true
  rules:
    - apiGroups: ["batch"]
      resources: ["jobs"]
      verbs: ["list", "delete"]
```

See [values.yaml](values.yaml) for all configurable values.
