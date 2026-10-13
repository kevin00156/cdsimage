# A small Linux machine with CODESYS Control for Linux SL on it: systemd as
# PID 1, the runtime installed the way its package installs it (sysv init script
# -> codesyscontrol.service), sshd, and a `plc` account with passwordless sudo.
# Tools written for a real controller (ssh + sudo + systemctl) work against it
# unchanged. Demo mode: no CodeMeter, the runtime stops ~2 h after it starts.
#
# The CODESYS packages are proprietary and never live in this repo. They come in
# through a named build context that points at a directory of .package files:
#
#   docker build --build-context packages=/path/to/packages \
#                --build-arg CDS_VERSION=4.20.0.0 -t cdsimage:4.20.0.0 .
#
# `./cdsimage build /path/to/packages` does exactly that and picks the version
# from the file name.
FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus openssh-server sudo \
        unzip procps iproute2 curl ca-certificates less \
 && rm -rf /var/lib/apt/lists/* \
 # host keys are per instance (see cdsimage-init), never baked into the image
 && rm -f /etc/ssh/ssh_host_* \
 # nothing for these to do in a container, and udev/getty only produce failures
 && systemctl mask systemd-udevd.service systemd-udevd-kernel.socket \
        systemd-udevd-control.socket getty.target console-getty.service

ARG CDS_VERSION
# Edge Gateway is optional: its .package may be absent, and the IDE can just as
# well reach the runtime through its own local gateway by IP:port.
RUN --mount=type=bind,from=packages,target=/pkg \
    test -n "$CDS_VERSION" || { echo "CDS_VERSION build arg is required"; exit 1; }; \
    mkdir /tmp/deb && cd /tmp/deb \
 && unzip -j "/pkg/CODESYS Control for Linux SL ${CDS_VERSION}.package" 'Delivery/linux/*_amd64.deb' \
 && for g in /pkg/CODESYS\ Edge\ Gateway\ for\ Linux\ *.package; do \
        [ -e "$g" ] && unzip -j -o "$g" 'Delivery/edgeamd64/*_amd64.deb'; done; \
    # Depends on codemeter, which demo mode does not need.
    (dpkg -i --force-depends ./*.deb || true) \
 && dpkg -s codesyscontrol | grep -q '^Status: install ok installed' \
 && rm -rf /tmp/deb

RUN useradd -m -s /bin/bash plc \
 && echo 'plc ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/plc && chmod 440 /etc/sudoers.d/plc

COPY sshd.conf /etc/ssh/sshd_config.d/cdsimage.conf
COPY cdsimage-init /usr/local/sbin/cdsimage-init
COPY cdsimage-init.service /etc/systemd/system/cdsimage-init.service
RUN systemctl enable cdsimage-init.service ssh.service

VOLUME ["/var/opt/codesys"]
EXPOSE 22 11740 1217
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
