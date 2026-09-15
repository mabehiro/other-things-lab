# other-things-lab

Supporting lab artifacts for experiments written up at
[otherthings.cloud](https://otherthings.cloud) — configurations, manifests,
scripts and topologies.

## What is here, and what is not

This repo holds **artifacts**: the things you would run.

The blog holds the **narrative and the evidence** — what I tried, what
happened, what I got wrong, the measurements and the packet captures. If you
want to know why something is configured the way it is, or whether it actually
worked, that is on the blog. If you want to reproduce it, it is here.

## Layout

One directory per experiment, named `YYYY-MM-<topic>`:

```
other-things-lab/
├── 2026-09-vxlan-evpn/
│   ├── README.md
│   ├── configs/
│   ├── systemd/
│   └── topology.txt
└── ...
```

## Use it however you like

Apache-2.0 — see [LICENSE](LICENSE). Copy it, adapt it, build on it. No
attribution beyond what the licence already asks for.

These are lab configs. They ran on my hardware, against the versions noted in
each experiment's README, and they carry no warranty of any kind. Read them
before you run them.
