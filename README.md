# cdsimage

**Disposable CODESYS soft PLCs in Docker.** One command starts a numbered
CODESYS Control for Linux SL instance with its own ports and its own
`/dev/shm`; another throws it away. Run as many side by side as you have
parallel jobs, on a machine other than the one with the IDE.

Made for logic benches: an IDE (or [cdsint](https://github.com/kevin00156/cdsint))
on a Windows laptop downloads to a runtime on a Linux box, and a companion
process talks to the PLC over shared memory, without a WSL VM eating the
laptop's RAM.

## What it needs

- Linux with Docker (BuildKit, the default since Docker 23).
- The CODESYS packages, which are **not** in this repo and never will be: they
  are proprietary. Get them from the CODESYS Store and put them in a directory
  of your own:
  - `CODESYS Control for Linux SL <version>.package` (required)
  - `CODESYS Edge Gateway for Linux <version>.package` (optional)

No license is needed: without one the runtime runs in demo mode and stops after
about two hours. `cdsimage restart N` starts the clock again.

## Build

```sh
./cdsimage build ~/codesys-packages            # newest Control version in the dir
./cdsimage build ~/codesys-packages 4.20.0.0   # or a given one
```

This tags `cdsimage:<version>` and `cdsimage:latest`. The packages reach the
build through a named build context, so they are never copied into this
directory. Match the runtime version to the device version in your project.

## Use

```sh
./cdsimage up cutter-a cutter-b   # waits until each accepts connections
./cdsimage ls
./cdsimage restart cutter-a       # after a download, or when the demo time runs out
./cdsimage reset cutter-b         # fresh container and fresh volume
./cdsimage down cutter-a cutter-b
./cdsimage log cutter-a           # follow the runtime log
```

An instance is named by a number (`1`) or a word (`cutter-a`). Instance
`<name>` is container `cds-<name>` with volume `cds-<name>-data`. A word gets
the lowest free number on first use and keeps it in
`~/.config/cdsimage/instances`, so its ports never move. Ports come from the
number `N`:

| | port |
|---|---|
| runtime (device address) | `11740+N` |
| Edge Gateway | `12170+N` |

Environment:

| variable | default | |
|---|---|---|
| `CDS_BIND` | `127.0.0.1` | address the ports are published on; set it to a LAN or Tailscale address to reach the PLC from another machine |
| `CDS_USER_MGMT` | `off` | `off` drops the runtime's forced user management, so a fresh instance takes a login and a download without creating an account first |
| `CDS_SEED` | none | a directory copied into a fresh instance's state (`/var/opt/codesys`) before it starts: a user database, a boot application |
| `CDS_IMAGE` | `cdsimage:latest` | image to run |

Put per-host defaults in `~/.config/cdsimage/env` (sourced as shell), for
example `CDS_BIND=100.64.0.1`, so a later `reset` recreates the instance on
the same address.

`CDS_USER_MGMT=off` together with `CDS_BIND` on a reachable address means
anyone who can reach the port can download to the PLC. Keep it on a private
network.

## Sharing instances between parallel jobs

A job holds an instance while it uses it, so two jobs never download onto the
same PLC:

```sh
bench=$(./cdsimage claim cutter- job-42)   # first free cutter-*, prints its name
./cdsimage restart "$bench"                 # fresh runtime, fresh 2 h demo clock
# ... download, test ...
./cdsimage release "$bench" job-42
```

Claiming again as the same owner renews the claim. A claim nobody renews
expires after `CDS_CLAIM_TTL` seconds (default 4 h), so a job that died does
not hold an instance forever. `ls` shows who holds what.

## Extending it on the host

What runs beside a PLC is yours, not this repo's. Two directories under
`~/.config/cdsimage/` take executables:

- `hooks.d/*` run after `up`, `restart`, `reset` and `down` as
  `<hook> <event> <name> <N>`. A restart gives the PLC a fresh `/dev/shm`, so a
  companion container (see below) has to be recreated after it; a hook does
  that, and nobody has to remember the order.
- `ssh.d/<cmd>` become extra commands for `cdsimage-ssh`, with stdin passed
  through (handy for shipping a binary: `gzip -c app | ssh <host> mycmd deploy 1`).

## Driving it from another machine

Give that machine's key a forced command, so it can manage instances and do
nothing else on the host (no shell, no Docker):

```
# ~/.ssh/authorized_keys on the Docker host
command="/path/to/cdsimage/cdsimage-ssh",restrict ssh-ed25519 AAAA... laptop
```

```powershell
ssh <host> restart cutter-a
ssh <host> ls
```

`cdsimage-ssh` allows `up`, `restart`, `reset`, `down`, `ls`, `log`, `claim`,
`release` and whatever is in `ssh.d/`. Do
not hand out Docker access (a `docker context` over SSH) instead: access to
the Docker daemon is root on the host.

## Reaching it from the IDE

The IDE's own local gateway (the CODESYS Gateway V3 service on Windows) can
reach the runtime directly: scan or enter the device address
`<host>:<11740+N>`. With cdsint:

```powershell
cdsint plc download -y --project <copy>.project --install 3.5.21.40 `
    --gateway <host> --port 11741 --gateway-name Gateway-1
```

## A companion process on shared memory

Every instance runs with `--ipc shareable`. Another container joins its IPC
namespace and sees the same `/dev/shm`, so whatever the IEC application
publishes with `SysSharedMemory*` is readable there under the same name, and
two instances never see each other's segments:

```yaml
services:
  bridge:
    image: my-bridge
    ipc: container:cds-1
    user: "1000"          # the runtime runs as uid 1000 and owns the segments
```

The runtime runs as uid 1000, not root. A companion with the same uid needs no
permission fixes on the segments.

## What it is not

- **Not for timing.** No PREEMPT_RT, no isolated cores. Cycle times and jitter
  measured here mean nothing for the real target. State machines, math, shm
  layout and HMI flows behave as they do on the target.
- **No fieldbus.** There is no NIC to drive; an EtherCAT master in the project
  stays unconfigured, as it does on any machine without the hardware.
- **Slow to start.** The runtime waits about 15 s for a CodeMeter that is not
  there before it comes up; `up` and `restart` wait for it.

## License

MIT for what is in this repo. CODESYS itself is licensed by CODESYS GmbH under
its own terms.
