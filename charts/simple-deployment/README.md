# simple-deployment

Runs a script that does not stop, as a Deployment.

## Example

Log the number of pods in the release namespace each minute:

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
