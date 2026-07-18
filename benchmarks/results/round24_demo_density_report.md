# Amber demo density: shared versus dedicated CPU

## Bottom line

The **$24 shared 2-vCPU / 4-GB Droplet is the cost winner**. It passed at 80 independent Amber apps, or **$0.30/app/month** at the measured edge. A safer 64-app operating cap leaves 20% measured headroom and costs **$0.375/app/month**.

| Host | Price | Disk | Measured healthy apps | Edge cost / app | Recommended cap | Recommended cost / app | First limit |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| $4 micro shared | $4.00 | 10 GB | 10 | $0.400 | 8 | $0.500 | storage reserve at 12 apps |
| 2 vCPU / 4 GB shared | $24.00 | 80 GB | 80 | $0.300 | 64 | $0.375 | burst p99 latency at 84 apps |
| 2 vCPU / 4 GB dedicated | $42.00 | 25 GB | 40 | $1.050 | 32 | $1.312 | storage reserve at 44 apps |

## What dedicated buys

At the same 40-app density, both equal-vCPU/equal-RAM plans delivered every request. Dedicated CPU reduced median burst p99 by **42%** and held observed CPU steal effectively at zero, but its 25-GB disk capped this large-data test at 40 apps.

| 40-app phase | Shared p99 median / max | Dedicated p99 median / max | Shared steal max | Dedicated steal max |
| --- | ---: | ---: | ---: | ---: |
| Steady | 92.4 / 104.2 ms | 75.3 / 78.5 ms | 0.15% | 0.01% |
| Burst | 130.8 / 149.5 ms | 76.1 / 76.9 ms | 4.83% | 0.00% |

## Boundary quality

| Host | Apps | Steady p99 median / max | Burst p99 median / max | Burst CPU max | Steal max | Free memory min |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| $4 micro shared | 10 | 83.8 / 85.0 ms | 83.8 / 86.1 ms | 28.3% | 0.35% | 145 MiB |
| 2 vCPU / 4 GB shared | 80 | 101.5 / 111.9 ms | 229.6 / 310.3 ms | 85.8% | 2.90% | 2294 MiB |
| 2 vCPU / 4 GB dedicated | 40 | 75.3 / 78.5 ms | 76.1 / 76.9 ms | 40.7% | 0.01% | 2854 MiB |

## Deployment choice

- **Best cost per app:** run up to 64 demos on `s-2vcpu-4gb` shared CPU for $0.375/app/month and retain 20% measured density headroom.
- **Lowest total bill:** run up to 8 demos on `s-1vcpu-512mb-10gb` for $0.50/app/month; its measured edge was 10 and disk, not compute, stopped density 12.
- **Best predictability:** run up to 32 demos on `c-2` dedicated CPU for $1.313/app/month; its measured edge was 40 and disk, not compute, stopped density 44.

## Validation

The synthesis contains **216 capacity trials plus 6 smoke trials**, with **90 cloned databases checked**, 0 integrity failures, 0 request errors, and 0 OOM kills. Each app had 1,000 routes, 10,000 users, one million resources, and a private 483,098,624-byte SQLite FULL database.

The shared host passed all three 80-app repetitions. At 84 apps, one of three bursts crossed the 1-second p99 gate while all requests still completed, establishing a latency-variance boundary rather than a crash boundary. Costs exclude the temporary load generator.
