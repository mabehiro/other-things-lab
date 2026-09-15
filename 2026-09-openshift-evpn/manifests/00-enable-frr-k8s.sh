#!/bin/bash
# The VTEP and RouteAdvertisements CRDs do not exist on a stock cluster.
# This enables FRR-K8s and route advertisement.
#
# Note the CR: network.operator.openshift.io, NOT the config one. Both are
# named `cluster`, and `oc get network cluster` returns the wrong one.
#
# This rolls out ovnkube-node with brief disruption -- do not run it mid-test.
set -eux

oc patch network.operator.openshift.io cluster --type=merge -p '{
  "spec": {
    "additionalRoutingCapabilities": { "providers": ["FRR"] },
    "defaultNetwork": { "ovnKubernetesConfig": { "routeAdvertisements": "Enabled" } }
  }
}'
