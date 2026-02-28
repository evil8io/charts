#!/usr/bin/env bash

set -xeufo pipefail

kubectl config set-context dummy
kubectl config use-context dummy

if ! kubectl --namespace "$NAMESPACE" get secret dhparam; then
    kubectl --namespace "$NAMESPACE" create secret generic dhparam --from-literal=dhparam.pem="$(openssl dhparam 4096 2>/dev/null)"
fi
