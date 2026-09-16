# 2026-09 · Advertising pod subnets into an EVPN fabric

A pod in an OpenShift 4.22 cluster reaching a plain VM behind a leaf switch,
as ordinary routed IP — no gateway host, no NAT, no translation. The cluster
nodes join the fabric as VTEPs in their own right.

Post: **Advertising pod subnets into an EVPN fabric with OpenShift 4.22** — https://otherthings.cloud/posts/advertising-pod-subnets-into-evpn-fabric/

```
AS 65000 · pod network 192.168.48.0/22 · tenant VRF via L3 VNI 101
cluster nodes 192.168.30.21-23 · underlay 192.168.30.0/24
```

See `topology.txt` — the nodes sit beside the leaves, not behind them.

## ⚠️ This needs the fabric first

**Not standalone.** The cluster peers into an EVPN fabric that has to already
exist, with a tenant VRF bound to L3 VNI 101:

1. [`../2026-09-vxlan-evpn/`](../2026-09-vxlan-evpn/) — the L2 fabric
2. [`../2026-09-evpn-l2-to-l3/`](../2026-09-evpn-l2-to-l3/) — the VRF and L3 VNI

`ipVRF.vni` in `02-cudn.yaml` **must** match the fabric's tenant L3 VNI. The two
sides are joined by that number and by `RT:65000:101` — never by name. The
cluster's VRF is called `cudn-tenant-a`, the fabric's is `tenant-a`, and that
mismatch is fine.

## Apply in order

The numbering is not decoration. Applying these out of order does not produce
an error — it produces objects that sit pending and blame each other.

| File | What |
|---|---|
| `00-enable-frr-k8s.sh` | enables FRR-K8s and route advertisement; the CRDs below do not exist without it |
| `nncp/evpn-vtep-cp*.yaml` | one dummy `/32` loopback per node — apply before the `VTEP` CR |
| `01-vtep.yaml` | before the CUDN — missing, and the NetworkAttachmentDefinition never renders |
| `02-cudn.yaml` | the tenant network. `transport` and `evpn` are siblings of `topology`, not children of `layer3` |
| `03-namespace.yaml` | both labels must be present **at creation** — see below |
| `04-frrconfiguration.yaml` | peers at the spine (route reflector), cluster ASN equal to the fabric's |
| `05-routeadvertisements.yaml` | `targetVRF` is mandatory and the CRD does not say so |
| `configs/frr-spine1-running.conf` | the fabric's route reflector, as it stands — including the `ipv4 unicast` reflection |
| `pods/tenant-pod.yaml` | a pod on the tenant network — nothing advertises a pod subnet until one exists |
| `pods/tenant-pod-2.yaml` | a second pod on a **different** node, for the pod-to-pod path |

## The VTEP goes on a dummy interface

OCP 4.22 *Advanced networking* §8.1.2: *"Avoid using an interface associated with a physical link carrier when using redundant BGP
peering. Instead, use a dummy interface where the IP is configured as the primary address."*

`nncp/` provisions `evpn-vtep0` with a single `/32` on each node, and `01-vtep.yaml` points `cidrs` at that range. The node's real NIC
keeps its own address — it is still the BGP peering address and still the physical path. Only the VTEP identity moves, because a VXLAN
device binds to a source address rather than to an interface.

**One policy per node.** The address differs per node and `nodeSelector` is the only way to vary it; a single policy would put the same
`/32` on all three. Each node must end up with **exactly one** address inside the VTEP CIDR, or the `VTEP` goes to a failed status.

⚠️ **The fabric must carry the loopback range.** OVN-Kubernetes advertises the VTEP IP on the underlay, but the fabric has to be
configured to receive it — the `/32`s need reflecting in `address-family ipv4 unicast`, not only in `l2vpn evpn`. While the VTEPs sit on
a connected subnet this is invisible; it is fatal the moment one moves off-subnet.

## Four things that cost time

**The CIDR is masked silently.** `layer3.subnets[].cidr` has no validation
requiring a masked network address — `layer2` does. A `/22` that does not start
on a multiple of four is accepted, masked, and used. The object keeps reporting
the value you typed while every pod and every route uses the masked one, and
`spec` is immutable, so the fix is deleting the CUDN and recreating every
namespace. Verify from inside a pod, never from the spec.

**`k8s.ovn.org/metadata.name` on the CUDN is required and nothing adds it.**
Without it the RouteAdvertisements selector matches nothing, and the two objects
each report the other as missing. Neither is the cause.

**`k8s.ovn.org/primary-user-defined-network` on the namespace is enforced on
UPDATE only**, so adding it after creation is denied and the namespace can never
host a primary network. It must be there when the namespace is created.

**`targetVRF: auto` is mandatory.** The CRD gives a free-form string, no enum, no
validation, and one line of description that does not say it is required. You
cannot even see the error until the selector above matches something.

## Testing it

`pods/tenant-pod.yaml` is enough for pod → `host-a`. Add `pods/tenant-pod-2.yaml` for pod → pod across nodes, which is a
**different path**: the two nodes are L2-adjacent, so that VXLAN goes VTEP to VTEP directly and the leaves are not in the
data path at all. A working pod → `host-a` ping proves nothing about it.

Both pin `nodeName` deliberately — the scheduler will otherwise put both pods on one node and the test proves nothing.

⚠️ `oc get pod -o wide` reports the **default-network** address, not the CUDN one. Read `ovn-udn1` from inside the pod.

## Versions

OpenShift **4.22.11**, EVPN GA in the default feature set. FRR **8.5.3** on the
fabric side. Five RHEL VMs plus a three-node cluster, all on one Proxmox host.

⚠️ **EVPN requires local gateway mode, and the OVN-Kubernetes CRD states that
setting it "means hardware offload will not be supported."** The two are
mutually exclusive on the same cluster.
