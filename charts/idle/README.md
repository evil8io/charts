# idle

Pre-provision Kubernetes node capacity by scheduling always-on idle pods. Wraps
[`spurin/idle`](https://github.com/spurin/idle) — a `scratch`-based container
that just calls `nanosleep` forever — and lets one release define many
independently-configurable pools.

## What you get

- A single cluster-scoped `PriorityClass` (default name `idle`, value
  `-1000000`, `globalDefault: false`) so idle pods are always preemptible by
  real workloads.
- One `Deployment` per entry under `.Values.deployments`, each with its own
  affinity / nodeSelector / tolerations / resources / topologySpread.
- A default `PodDisruptionBudget` per deployment with `maxUnavailable: 100%` —
  it registers the workload as PDB-aware without actually blocking any
  disruption (idle pods are preemptible placeholders). Override per-deployment
  to enforce a real budget; when switching to `minAvailable`, also set
  `maxUnavailable: null` so the defaults-merge doesn't leave both fields set.
- Optional `ServiceAccount` and KEDA `ScaledObject` per deployment.

## Config model

Top-level `defaults:` is deep-merged with each `deployments.<name>` override
(`mergeOverwrite (deepCopy defaults) override`). Only specify what differs.

### Autoscaling

KEDA `ScaledObject` is the only autoscaler this chart emits — KEDA creates the
HPA for you, so shipping a second HPA path would cause two controllers to
fight over `spec.replicas`. When `scaledObject.enabled: true`, the chart
**omits** `spec.replicas` on the Deployment. If you sync with Argo CD, add
`spec.replicas` to `ignoreDifferences` for those deployments.

### Pod anti-affinity convenience

`podAntiAffinity: { enabled, mode: soft|hard, topologyKey, weight }` synthesises
an anti-affinity stanza keyed on `idle.evil8.io/deployment=<name>`. Raw
`affinity:` is still honoured and merged with the synthesised block.

## Example

```yaml
priorityClass:
  name: idle
  value: -1000000

defaults:
  resources:
    requests: {cpu: 10m, memory: 8Mi}
    limits:   {cpu: 50m, memory: 32Mi}

deployments:
  warm-general:
    replicas: 20
    podAntiAffinity:
      enabled: true
      mode: soft

  warm-arm64:
    replicas: 5
    nodeSelector:
      kubernetes.io/arch: arm64

  warm-cron:
    scaledObject:
      enabled: true
      minReplicaCount: 1
      maxReplicaCount: 50
      triggers:
        - type: cron
          metadata:
            timezone: UTC
            start: "0 8 * * MON-FRI"
            end:   "0 18 * * MON-FRI"
            desiredReplicas: "50"
    pdb:
      minAvailable: 1
      maxUnavailable: null   # override the default "100%"
```

## Guardrails

The chart fails rendering (with a clear message) if:

- a PDB is `enabled: true` but both `minAvailable` and `maxUnavailable` are set
  (or neither is set);
- a `scaledObject.enabled: true` deployment has an empty `triggers:` list.
