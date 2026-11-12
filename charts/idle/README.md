# idle

Reserves node capacity with idle pods that every other workload can preempt. The pods run
[`spurin/idle`](https://github.com/spurin/idle), a container that only sleeps. One release
can contain many pools of idle pods, each with its own configuration.

## What you get

- One `PriorityClass` for the release, with the name `idle` and the value `-1000000`.
- One `Deployment` for each entry under `deployments`.
- One `PodDisruptionBudget` for each deployment. The default is `maxUnavailable: 100%`,
  which does not block a disruption.
- Optionally, a `ServiceAccount` and a KEDA `ScaledObject` for each deployment.

## Configuration

Each entry under `deployments` starts from `defaults`. Set only the keys that differ.

- `podAntiAffinity` spreads the pods of one deployment across nodes. Set `mode` to `soft`
  or `hard`. The result is merged with `affinity`.
- `scaledObject` needs [KEDA](https://keda.sh) and at least one entry in `triggers`. KEDA
  then sets the replica count in place of `replicas`.
- `pdb` accepts `minAvailable` or `maxUnavailable`, not both. To use `minAvailable`, also
  set `maxUnavailable: null`.

## Example

```yaml
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
      maxUnavailable: null
```
