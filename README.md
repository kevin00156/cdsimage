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
./cdsimage up 1 2 3      # three instances, waits until each accepts connections
./cdsimage ls
./cdsimage restart 2     # after a download, or when the demo time runs out
./cdsimage reset 3       # fresh container and fresh volume
./cdsimage down 1 2 3
./cdsimage log 1         # follow the runtime log
```

Instance `N` is container `cds-N` with volume `cds-N-data`, and its ports come
from its number:

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

`CDS_USER_MGMT=off` together with `CDS_BIND` on a reachable address means
anyone who can reach the port can download to the PLC. Keep it on a private
network.

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
