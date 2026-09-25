#!/usr/bin/env bash
# shellcheck disable=SC2153

# Set the DEBUG environment variable to enable debug output
test -n "$DEBUG" && set -x

set -ufo pipefail

export LC_ALL=C

state_configmap="${STATE_CONFIGMAP}"
interval="${INTERVAL}"
heartbeat=/tmp/heartbeat

removal_label="${REMOVAL_LABEL}"
removal_annotation="${REMOVAL_ANNOTATION}"
removal_settle="${REMOVAL_SETTLE}"

crd_label="${CRD_LABEL}"
crd_annotation="${CRD_ANNOTATION}"
crd_settle="${CRD_SETTLE}"

timestamp_pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

state_loaded=false
addresses=""
removal_at=""
removal_stored=""
removal_handled=""
crd_handled=""

function logger() {
  echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ) level=$1 msg=\"$2\""
}

# No --request-timeout: a client config override disables the in-cluster fallback of kubectl.
function k() {
  timeout 15s kubectl "$@"
}

function epoch() {
  jq -rn --arg t "$1" '$t | fromdateiso8601'
}

function load_state() {
  local value

  value="$(k --namespace="$NAMESPACE" get configmap "$state_configmap" -o json | jq -r '.data["apiserver-removal-at"] // ""')" || return 1

  if [[ -n "$value" && ! "$value" =~ $timestamp_pattern ]]; then
    logger "warn" "ignoring the invalid apiserver-removal-at value $value"
    value=""
  fi

  removal_at="$value"
  removal_stored="$value"
  state_loaded=true
  logger "info" "loaded the state, apiserver-removal-at=$value"
}

function store_removal() {
  k --namespace="$NAMESPACE" get configmap "$state_configmap" -o json \
    | jq --arg at "$removal_at" '.data["apiserver-removal-at"] = $at' \
    | k --namespace="$NAMESPACE" replace -f - >/dev/null
}

function read_addresses() {
  k --namespace=default get endpointslice kubernetes -o json \
    | jq -r '.endpoints[]?.addresses[]?' \
    | sort -u
}

function read_crd_at() {
  k get customresourcedefinitions --no-headers \
    | awk '{print $2}' \
    | sort \
    | tail -n1
}

function due() {
  local at="$1" handled="$2" settle="$3" now="$4"

  [ -n "$at" ] && [ "$at" != "$handled" ] && [ $((now - $(epoch "$at"))) -ge "$settle" ]
}

function restart_targets() {
  local label="$1" annotation="$2" at="$3" targets patch kind ns name failed=0

  targets="$(
    k get deployments,statefulsets,daemonsets --all-namespaces --selector="$label=true" -o json \
      | jq -r --arg annotation "$annotation" --arg at "$at" '
          .items[]
          | select(.kind != "StatefulSet" or .spec.updateStrategy.type != "OnDelete")
          | select((.spec.template.metadata.annotations[$annotation] // "") < $at)
          | [(.kind | ascii_downcase), .metadata.namespace, .metadata.name]
          | @tsv'
  )" || {
    logger "warn" "cannot list the workloads with $label=true"
    return 1
  }

  patch="$(jq -cn --arg annotation "$annotation" --arg at "$at" '{spec: {template: {metadata: {annotations: {($annotation): $at}}}}}')"

  while IFS=$'\t' read -r kind ns name; do
    [ -n "$kind" ] || continue

    if k --namespace="$ns" patch "$kind" "$name" --type=merge --patch="$patch" >/dev/null; then
      logger "info" "restarted $kind $ns/$name, $annotation=$at"
    else
      logger "warn" "cannot restart $kind $ns/$name"
      failed=1
    fi
  done <<<"$targets"

  return "$failed"
}

function pass() {
  local current crd_at removed now

  if [ "$state_loaded" != true ]; then
    load_state || {
      logger "warn" "cannot read the configmap $state_configmap, skipping the pass"
      return
    }
  fi

  current="$(read_addresses)" || {
    logger "warn" "cannot read the kubernetes endpointslice, skipping the pass"
    return
  }

  if [ -z "$current" ]; then
    logger "warn" "the kubernetes endpointslice has no addresses, skipping the pass"
    return
  fi

  crd_at="$(read_crd_at)" || {
    logger "warn" "cannot list the customresourcedefinitions, skipping the pass"
    return
  }

  if [[ ! "$crd_at" =~ $timestamp_pattern ]]; then
    logger "warn" "cannot find the newest customresourcedefinition, skipping the pass"
    return
  fi

  if [ -n "$addresses" ]; then
    removed="$(comm -23 <(echo "$addresses") <(echo "$current") | paste -sd, -)"

    if [ -n "$removed" ]; then
      removal_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      logger "info" "api server removed: $removed, apiserver-removal-at=$removal_at"
    fi
  fi

  if [ "$addresses" != "$current" ]; then
    logger "info" "api servers: $(echo "$current" | paste -sd, -)"
  fi

  addresses="$current"

  if [ -n "$removal_at" ] && [ "$removal_at" != "$removal_stored" ]; then
    if store_removal; then
      removal_stored="$removal_at"
    else
      logger "warn" "cannot update the configmap $state_configmap"
    fi
  fi

  now="$(date +%s)"

  if due "$removal_at" "$removal_handled" "$removal_settle" "$now"; then
    restart_targets "$removal_label" "$removal_annotation" "$removal_at" && removal_handled="$removal_at"
  fi

  if due "$crd_at" "$crd_handled" "$crd_settle" "$now"; then
    restart_targets "$crd_label" "$crd_annotation" "$crd_at" && crd_handled="$crd_at"
  fi
}

logger "info" "starting, removal settle $removal_settle s, crd settle $crd_settle s"

while true; do
  start="$(date +%s)"
  date +%s >"$heartbeat"

  pass

  elapsed=$(($(date +%s) - start))

  if [ "$elapsed" -gt "$interval" ]; then
    logger "warn" "the pass took $elapsed s"
  fi

  sleep $((elapsed < interval ? interval - elapsed : 0))
done
