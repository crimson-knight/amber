# Amber V2 shared-versus-dedicated demo density benchmark

## Objective

Find the lowest monthly infrastructure cost per healthy Amber demo application,
while separating cheap shared-CPU capacity from predictable dedicated-CPU
capacity.

This is not a single-server maximum-throughput benchmark. It increases the
number of independent Amber applications on one host and requires every tenant
to remain usable under a sustained demo workload and a simultaneous burst.

## Plan matrix

The provisioning script resolves current prices from the authenticated
DigitalOcean account and records them in the inventory. The default matrix is:

| Label | Size | CPU class | Purpose |
| --- | --- | --- | --- |
| `micro` | `s-1vcpu-512mb-10gb` | Shared | $4-class low-cost control |
| `shared2x4` | `s-2vcpu-4gb` | Shared | Equal vCPU/RAM comparison |
| `dedicated2x4` | `c-2` | Dedicated | Equal vCPU/RAM comparison |

A separate `c-4` dedicated-CPU load generator prevents client-side CPU
contention from becoming the measured bottleneck. All traffic uses private VPC
addresses in one region.

## One demo application

Every tenant is a separate release-built Amber V2 process with:

- 1,000 installed routes.
- A private SQLite WAL database using `synchronous=FULL`.
- 10,000 users and 1,000,000 realistic 240-byte resources.
- Integer, UUID, ULID, and owner-list indexed lookups.
- Bearer-session hashing and an indexed session read on authenticated requests.
- Bcrypt cost-10 login, SHA-256 calculation, updates, and full CRUD cycles.
- A bounded database pool and an individual systemd cgroup.

Each process receives equal CPU and I/O weight, a one-core CPU ceiling, a
192 MiB soft memory boundary, a 256 MiB hard boundary, and a 128-task limit.
The limits prevent one broken demo from consuming the whole host while still
allowing measured memory pressure to determine density.

## Traffic and pass criteria

The runner checks densities `1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 28, 32,
36, 40, 44, 48, 56, 64, 80, 96, 112, 128` until a target fails. Each tested
density runs twice in rotated phase order. The larger range makes storage
exhaustion, CPU saturation, or latency failure visible instead of reporting
only a lower capacity bound.

| Phase | Offered traffic | Duration | Required p99 | Required attainment |
| --- | ---: | ---: | ---: | ---: |
| Steady demo use | 2 RPS per app | 30 s | <=250 ms | >=95% |
| Simultaneous burst | 10 RPS per app | 20 s | <=1,000 ms | >=95% |

The deterministic request mix is 2% bcrypt login, 80% indexed reads/lists, 8%
SHA-256 calculation, 6% updates, and 4% create/read/update/delete cycles.

A density counts only when every phase repetition has:

- Zero HTTP, application, connection, and load-generator errors.
- At least the required offered-load attainment and cross-app fairness.
- All Amber systemd units still active with no OOM kill.
- No configured swap and no swap activity.
- At least 5% host memory still available.

The report records CPU utilization, CPU steal, I/O wait, disk utilization,
page faults, aggregate process memory, per-app throughput, fairness, and p99.
Monthly plan price divided by the highest passing density is the production
host cost per healthy demo. The temporary load generator is not included.

## Reproduction

Build the Linux objects first using the existing Round 23 cross-compiler flow,
then run:

```shell
APPLY=1 benchmarks/digitalocean/provision_demo_density_lab.sh
OBJECT_DIR=/tmp/amber-database-r23-objects benchmarks/digitalocean/deploy_demo_density_lab.sh
ruby benchmarks/bin/demo_density_digitalocean.rb \
  --inventory=benchmarks/digitalocean/amber-density-r24-inventory.json
APPLY=1 benchmarks/digitalocean/destroy_demo_density_lab.sh
```

Validate the local gate and load-generator code with:

```shell
ruby benchmarks/bin/test_demo_density_round24.rb
```

## Results

Results will be recorded after the hosted matrix completes. Raw trial evidence
belongs in `benchmarks/results/round24_digitalocean_demo_density.json`; this
document must distinguish the equal-resource shared/dedicated comparison from
the lower-cost micro control.
