# Which OVN rule keeps two NoOverlay networks apart

Why this file exists: the post shows that a ping from network A to network B
is dropped inside the source node, and names the OVN rule that drops it. These
are the commands that find that rule, so you can check it on your own cluster
instead of taking the post's word for it.

Everything here only reads. Nothing changes the cluster.

Assumes both CUDNs from this directory are applied and advertised (A and B),
with a test pod in each. The names below are the ones the manifests produce.
The pod IPs and MACs are the ones from the post's run; yours may differ, so
read them off your own cluster in step 2.

OVN-Kubernetes runs with interconnect, so each node has its own OVN databases.
Run everything against the `ovnkube-node` pod on the node where the source pod
runs. In the post that's `ocp-nooverlay-cp1`.

## 1 · Find the ovnkube-node pod on the source node

```bash
OVNP=$(oc get pod -n openshift-ovn-kubernetes -l app=ovnkube-node \
  --field-selector spec.nodeName=ocp-nooverlay-cp1 -o name)
echo "$OVNP"
```

## 2 · Collect the three values ovn-trace needs

The logical switch for network A on this node. Look for the name with
`nooverlay.a` and the node name, e.g. `cluster_udn_cudn.nooverlay.a_ocp-nooverlay-cp1`:

```bash
oc exec -n openshift-ovn-kubernetes $OVNP -c nbdb -- ovn-nbctl ls-list
```

The source pod's logical switch port. The `name` on the line with the pod's IP,
e.g. `nooverlay.a.cudn.nooverlay.a_nooverlay-a_nooverlay-pod-1`:

```bash
oc exec -n openshift-ovn-kubernetes $OVNP -c nbdb -- \
  ovn-nbctl --format=csv --columns=name,addresses list Logical_Switch_Port | grep "192.168.54.5"
```

The gateway MAC the pod sends to: the `lladdr` of its `.1` neighbour. Ping
something first if the entry is missing.

```bash
oc exec -n nooverlay-a nooverlay-pod-1 -- ip neigh show dev ovn-udn1
```

## 3 · Trace A → B

In OVN, each network on each node is a logical switch, and every pod plugs
into it through its own logical switch port. The port's name is how
`ovn-trace` knows where the made-up packet enters. That's why the trace
command starts with `inport == "<the port>"`, and the matching database table
is called `Logical_Switch_Port`.

In the trace, A's pod-1 is the port
`nooverlay.a.cudn.nooverlay.a_nooverlay-a_nooverlay-pod-1` on the switch
`cluster_udn_cudn.nooverlay.a_ocp-nooverlay-cp1`.

`ovn-trace` runs a made-up packet through OVN's logical rules and prints every
rule it matches. Nothing is sent. `--ct=new` traces it as the first packet of
a new connection.

```bash
SW='cluster_udn_cudn.nooverlay.a_ocp-nooverlay-cp1'            # Logical Switch
LSP='nooverlay.a.cudn.nooverlay.a_nooverlay-a_nooverlay-pod-1'  # Logical Switch Port
GWMAC='0a:58:c0:a8:36:01'

oc exec -n openshift-ovn-kubernetes $OVNP -c northd -- ovn-trace --ct=new "$SW" \
  "inport == \"$LSP\" && eth.src == 0a:58:c0:a8:36:05 && eth.dst == $GWMAC && ip4.src == 192.168.54.5 && ip4.dst == 192.168.56.4 && ip.ttl == 64 && icmp4.type == 8"
```

Output from the post's run (2026-10-15):

```text
# icmp,reg14=0x4,vlan_tci=0x0000,dl_src=0a:58:c0:a8:36:05,dl_dst=0a:58:c0:a8:36:01,nw_src=192.168.54.5,nw_dst=192.168.56.4,nw_tos=0,nw_ecn=0,nw_ttl=64,nw_frag=no,icmp_type=8,icmp_code=0

ingress(dp="cluster_udn_cudn.nooverlay.a_ocp-nooverlay-cp1", inport="nooverlay.a.cudn.nooverlay.a_nooverlay-a_nooverlay-pod-1")
-------------------------------------------------------------------------------------------------------------------------------
 0. ls_in_check_port_sec (northd.c:10205): 1, priority 50, uuid 87533f9b
    reg0[15] = check_in_port_sec();
    next;
 5. ls_in_pre_acl (northd.c:6490): ip, priority 100, uuid a185708c
    reg0[0] = 1;
    next;
 7. ls_in_pre_stateful (northd.c:6755): reg0[0] == 1, priority 100, uuid fcba627f
    ct_next(dnat);

ct_next(ct_state=new|trk)
-------------------------
 8. ls_in_acl_hint (northd.c:6814): ct.new && !ct.est, priority 7, uuid 0792386e
    reg0[7] = 1;
    reg0[9] = 1;
    reg0[1] = 1;
    next;
 9. ls_in_acl_eval (northd.c:7997): ip && !ct.est, priority 1, uuid 73b2374c
    next;
11. ls_in_acl_action (northd.c:7798): 1, priority 0, uuid 44dc4745
    reg8[16] = 0;
    reg8[17] = 0;
    reg8[18] = 0;
    next;
20. ls_in_acl_after_lb_eval (northd.c:7608): reg8[30..31] == 0 && reg0[9] == 1 && ((ip4.src == $a10109792604843350142 && ip4.dst == $a10109792604843350142)), priority 2050, uuid a5d41540
    reg8[17] = 1;
    next;
22. ls_in_acl_after_lb_action (northd.c:7781): reg8[17] == 1, priority 1000, uuid 0a013686
    reg8[16] = 0;
    reg8[17] = 0;
    reg8[18] = 0;
    reg8[30..31] = 0;
```

How to read it:

- The `#` line is the packet `ovn-trace` built from your match.
- `ingress(dp=…, inport=…)` is the switch and the port it enters through.
- Each numbered line is one rule that matched: `<table>. <table name>
  (<source line>): <match>, priority <n>, uuid <id>`. The indented lines under
  it are what the rule did. `next;` means "go on to the next table".
- `ct_next(ct_state=new|trk)` is the packet going through conntrack. It comes
  back as a new connection because of `--ct=new`.
- **The answer is table 20.** Source and destination are both in the address
  set `$a10109792604843350142`, so the rule sets `reg8[17]`, the drop verdict.
- Table 22 matches `reg8[17] == 1` and doesn't say `next;`, so nothing comes
  after it. The packet goes no further.

## 4 · Trace A → A, the control

The same packet to a pod on A's own network, which the ping reaches:

```bash
oc exec -n openshift-ovn-kubernetes $OVNP -c northd -- ovn-trace --ct=new "$SW" \
  "inport == \"$LSP\" && eth.src == 0a:58:c0:a8:36:05 && eth.dst == $GWMAC && ip4.src == 192.168.54.5 && ip4.dst == 192.168.52.5 && ip.ttl == 64 && icmp4.type == 8"
```

What to look for: the same stage at priority 2100, matching A's own `/22` on
both sides. It wins over the 2050 drop, and the trace carries on past it.

## 5 · What's in the address set

Take the `$a…` name from step 3's output, without the `$`:

```bash
oc exec -n openshift-ovn-kubernetes $OVNP -c nbdb -- \
  ovn-nbctl find Address_Set name=a10109792604843350142
```

`addresses` lists every advertised network's subnet. `external_ids` shows who
created it: `"k8s.ovn.org/owner-type"=AdvertisedNetwork`.

## 6 · The ACLs behind those rules, and who owns them

```bash
oc exec -n openshift-ovn-kubernetes $OVNP -c nbdb -- \
  ovn-nbctl find ACL 'external_ids:"k8s.ovn.org/owner-type"=AdvertisedNetwork'
```

Expect one drop ACL at priority 1050 that uses the address set, and one pass
ACL at 1100 per advertised network. ACL priorities show up in the logical
flows as 1000 more, which is why the traces read 2050 and 2100.

## 7 · Optional: what reg8[17] does

The eval stage only sets a verdict bit. The action stage after it acts on it.
This lists the action stage's rules; the one matching `reg8[17] == 1` is the
drop:

```bash
oc exec -n openshift-ovn-kubernetes $OVNP -c sbdb -- \
  ovn-sbctl lflow-list | grep ls_in_acl_after_lb_action
```
