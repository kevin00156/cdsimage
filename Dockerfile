# CODESYS Control for Linux SL in a container, demo mode, no systemd, no root.
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

RUN apt-get update && apt-get install -y --no-install-recommends unzip procps iproute2 \
 && rm -rf /var/lib/apt/lists/*

# Our own fixed uid, created before the debs so theirs (codesysedge makes one,
# codesyscontrol 4.20 does not) can never take 1000. Shm segments the runtime
# creates are owned by this uid, which is what a sidecar sharing the IPC
# namespace has to match.
RUN useradd -u 1000 -m plc

ARG CDS_VERSION
# Edge Gateway is optional: its .package may be absent, and the IDE can just as
# well reach the runtime through its own local gateway by IP:port.
RUN --mount=type=bind,from=packages,target=/pkg \
    test -n "$CDS_VERSION" || { echo "CDS_VERSION build arg is required"; exit 1; }; \
    mkdir /tmp/deb && cd /tmp/deb \
 && unzip -j "/pkg/CODESYS Control for Linux SL ${CDS_VERSION}.package" 'Delivery/linux/*_amd64.deb' \
 && for g in /pkg/CODESYS\ Edge\ Gateway\ for\ Linux\ *.package; do \
        [ -e "$g" ] && unzip -j -o "$g" 'Delivery/edgeamd64/*_amd64.deb'; done; \
    # Depends on codemeter + systemd; demo mode needs neither, and postinst's
    # systemctl calls fail harmlessly. We start the binaries ourselves.
    (dpkg -i --force-depends ./*.deb || true) \
 && dpkg -s codesyscontrol | grep -q '^Status: install ok installed' \
 && rm -rf /tmp/deb

# Run everything as plc, not as root. The runtime hands its API sockets to the
# codesyscontrolapi group (created by the deb), so plc has to be in it.
RUN usermod -aG codesyscontrolapi plc \
 && mkdir -p /var/opt/codesys /var/opt/codesysedge /var/opt/codesyscontrolapi \
 && chown -R plc: /opt/codesys /var/opt/codesys /var/opt/codesysedge /var/opt/codesyscontrolapi /etc/codesyscontrol \
 && { [ ! -d /etc/codesysedge ] || chown -R plc: /opt/codesysedge /etc/codesysedge; }

COPY entrypoint.sh /entrypoint.sh
USER plc
VOLUME ["/var/opt/codesys"]
EXPOSE 11740 1217
ENTRYPOINT ["/entrypoint.sh"]
