# 2026-10 · Running pods without an overlay on OpenShift 4.22

A NoOverlay CUDN: pod traffic between nodes leaves as plain IP, with no Geneve
header, and each node's pod `/24` is advertised over BGP. A pod reaches a host
outside the cluster with its own address, and that host reaches it back, with
no host settings changed on the nodes. A second NoOverlay network shares the
same routing table and still can't reach the first.

Post: **Running pods without an overlay on OpenShift 4.22** — https://otherthings.cloud/posts/nooverlay-cudn-on-the-fabric/

```
AS 65000 · network A 192.168.52.0/22 · network B 192.168.56.0/22
nodes 192.168.20.51-53 (primary NIC, br-ex) · route reflector 192.168.20.25
```

See `topology.txt`.

## ⚠️ This needs spine1 first

**Not standalone.** The nodes peer with `spine1`, the route reflector from
[`../2026-09-vxlan-evpn/`](../2026-09-vxlan-evpn/). This directory adds a
VLAN 20 leg and a `nooverlay` peer group to it. It doesn't build it.

Any BGP router that reflects IPv4 unicast between the three nodes will do.
What matters is that it's reachable on the nodes' primary network, and that
`route-reflector-client` is set under `address-family ipv4 unicast`.

## ⚠️ This cluster can't be upgraded

NoOverlay is Technology Preview in 4.22 and needs `featureSet:
TechPreviewNoUpgrade`. That cannot be undone and blocks minor-version updates.
Build a cluster you can throw away.

## Build in order

| File | What |
|---|---|
| `install/install-config.example.yaml` | `TechPreviewNoUpgrade`; the default network stays on Geneve |
| `install/agent-config.yaml` | three nodes, static addresses, one default route |
| `install/openshift/cluster-network-03-config.yml` | FRR and route advertisements from day 0. Goes in `openshift/`, not `manifests/` |
| `configs/spine1-vlan20.sh` | spine1's address on VLAN 20, plus the listen range to add |
| `configs/frr-spine1-running.conf` | spine1 as it stood, read back off the box |
| `manifests/01-namespace.yaml` | the primary-UDN label must be there **at creation** |
| `manifests/02-cudn.yaml` | network A, `transport: NoOverlay` and nothing else |
| `manifests/03-frrconfiguration.yaml` | the session to spine1, on the primary NIC |
| `manifests/04-routeadvertisements.yaml` | until this exists, the CUDN reports `TransportAccepted False` |
| `manifests/05-test-pods.yaml` | two NoOverlay pods and two Geneve pods, pinned to different nodes |
| `manifests/06`–`10` | network B, for the isolation test. Same order: namespace, CUDN, FRRConfiguration, RouteAdvertisements, pods |
| `isolation-trace.md` | the `ovn-trace` and database commands that find the rule dropping A → B |

## Things that cost time

**`noOverlayOptions` doesn't exist.** The 4.22 docs show it on the CUDN. On
4.22.11, with the feature gate on, `oc explain` says the field does not exist.
The CUDN carries `transport` alone.

**`TransportAccepted` is `False` until something advertises the network.** The
message is *"No RouteAdvertisements CR is advertising the pod networks"*. It
turns `True` once `04` is applied. Nothing is wrong in between.

**Peer on the primary NIC.** The first build peered over a second NIC on
VLAN 30, copied from the EVPN cluster. East-west worked, but traffic from
outside the cluster to a pod didn't come back without changing the nodes' host
settings. Peering over VLAN 20 (`br-ex`) round-trips with none.

**`toReceive` is required.** Without it each node rejects the other nodes'
`/24`s that spine1 reflects, and east-west falls to the default route without
an error.

## Testing it

`oc get pod -o wide` reports the default-network address. Read the CUDN address
from inside the pod: `ip -4 addr show ovn-udn1`.

Both pairs in `05` pin `nodeName`, because two pods on one node don't cross the
underlay. Change the node names to match yours.

## Versions

OpenShift **4.22.11**, `TechPreviewNoUpgrade`, shared gateway mode. FRR
**8.5.3** on spine1. Three nested VMs on one Proxmox host. Nothing here
measures performance.
