# simple-cronjob

Runs a script on a schedule, as a CronJob.

## Example

Delete the successful Jobs in the release namespace each hour:

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
