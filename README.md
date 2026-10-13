# cdsimage

**Disposable CODESYS controllers in Docker.** Each instance is a container that
behaves like a small Linux controller: systemd, `codesyscontrol.service`
installed the way its package installs it, sshd, and a `plc` account with
passwordless sudo. Whatever you use to deploy to a real controller (ssh + sudo
+ systemctl scripts, your Makefile, the IDE) works against it unchanged. One
command starts one; another throws it away. Run as many side by side as you
have parallel jobs, on a machine other than the one with the IDE.

Made for logic benches: an IDE (or [cdsint](https://github.com/kevin00156/cdsint))
on a Windows laptop downloads to a runtime on a Linux box, and your own
services run beside it the way they do on the target, without a WSL VM eating
the laptop's RAM.

## What it needs

- Linux with Docker 28 or later (BuildKit, and `--security-opt
  writable-cgroups=true`, which lets systemd run without `--privileged`).
- The CODESYS packages, which are **not** in this repo and never will be: they
  are proprietary. Get them from the CODESYS Store and put them in a directory
  of your own:
  - `CODESYS Control for Linux SL <version>.package` (required)
  - `CODESYS Edge Gateway for Linux <version>.package` (optional)

No license is needed: without one the runtime runs in demo mode and stops about
two hours after it starts. Restarting `codesyscontrol` (or the instance) starts
the clock again.

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
echo 'CDS_BIND=100.64.0.1' > ~/.config/cdsimage/env      # where to publish (default 127.0.0.1)
cat ~/.ssh/id_ed25519.pub >> ~/.config/cdsimage/authorized_keys   # who may ssh in as plc

./cdsimage up cutter-a cutter-b   # waits until each runtime accepts connections
./cdsimage ls
ssh -p 2203 plc@100.64.0.1        # a shell on cutter-a; sudo works
./cdsimage restart cutter-a       # reboot it
./cdsimage reset cutter-b         # a fresh machine: new container, new volume
./cdsimage down cutter-a cutter-b
./cdsimage log cutter-a           # follow the runtime log
```

An instance is named by a number (`1`) or a word (`cutter-a`). Instance
`<name>` is container `cds-<name>` with volume `cds-<name>-data`. A word gets
the lowest free number on first use and keeps it in
`~/.config/cdsimage/instances`, so its ports never move, and its ssh host key
lives in `~/.config/cdsimage/hostkeys/<name>`, so a reset does not trip your
`known_hosts`. Ports come from the number `N`:

| | port |
|---|---|
| ssh (user `plc`) | `2200+N` |
| runtime (device address) | `11740+N` |
| Edge Gateway | `12170+N` |

An ssh config entry per instance makes it a host like any other:

```
Host cutter-a
  HostName 100.64.0.1
  Port 2203
  User plc
  StrictHostKeyChecking accept-new
```

Environment (put per-host values in `~/.config/cdsimage/env`, sourced as shell,
so a later `reset` recreates the instance the same way):

| variable | default | |
|---|---|---|
| `CDS_BIND` | `127.0.0.1` | address the ports are published on |
| `CDS_AUTHORIZED_KEYS` | `~/.config/cdsimage/authorized_keys` | keys allowed to log in as `plc`; read live, edits apply at once |
| `CDS_USER_MGMT` | `off` | `off` drops the runtime's forced user management, so a fresh instance takes a login and a download without creating an account first |
| `CDS_SEED` | none | a directory copied into a fresh instance's `/var/opt/codesys` before the runtime starts: a user database, a boot application |
| `CDS_IMAGE` | `cdsimage:latest` | image to run |

`CDS_USER_MGMT=off` together with `CDS_BIND` on a reachable address means
anyone who can reach the port can download to the PLC. Keep it on a private
network.

## Sharing instances between parallel jobs

A job holds an instance while it uses it, so two jobs never download onto the
same PLC:

```sh
bench=$(./cdsimage claim cutter- job-42)   # first free cutter-*, prints its name
# ... deploy, download, test ...
./cdsimage release "$bench" job-42
```

Claiming again as the same owner renews the claim. A claim nobody renews
expires after `CDS_CLAIM_TTL` seconds (default 4 h), so a job that died does
not hold an instance forever. `ls` shows who holds what.

## Managing instances from another machine

Logging in to an instance is ordinary ssh. Managing them (claim, restart,
reset) needs the Docker host, so give the other machine a second key there with
a forced command: it can run `cdsimage` and nothing else (no shell, no Docker):

```
# ~/.ssh/authorized_keys on the Docker host
command="/path/to/cdsimage/cdsimage-ssh",restrict ssh-ed25519 AAAA... laptop
```

```sh
ssh <docker-host> claim cutter- job-42
ssh <docker-host> restart cutter-a
```

`cdsimage-ssh` allows `up`, `restart`, `reset`, `down`, `ls`, `log`, `claim`
and `release`. Do not hand out Docker access (a `docker context` over SSH)
instead: access to the Docker daemon is root on the host. A shell inside an
instance is root only in that container.

## Reaching it from the IDE

The IDE's own local gateway (the CODESYS Gateway V3 service on Windows) can
reach the runtime directly: scan or enter the device address
`<host>:<11740+N>`. With cdsint:

```powershell
cdsint plc download -y --project <copy>.project --install 3.5.21.40 `
    --gateway <host> --port 11743 --gateway-name Gateway-1
```

## What it is not

- **Not for timing.** No PREEMPT_RT, no isolated cores. Cycle times and jitter
  measured here mean nothing for the real target. State machines, math, shm
  layout and service wiring behave as they do on the target.
- **No fieldbus.** There is no NIC to drive; an EtherCAT master in the project
  stays unconfigured, as it does on any machine without the hardware.
- **Slow to start.** The runtime waits about 15 s for a CodeMeter that is not
  there before it comes up; `up` and `restart` wait for it.

## License

MIT for what is in this repo. CODESYS itself is licensed by CODESYS GmbH under
its own terms.
