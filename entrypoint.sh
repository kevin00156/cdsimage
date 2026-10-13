#!/bin/bash
# Stands in for the two systemd units: start the runtime (and the Edge Gateway
# when it is installed), and exit as soon as either dies so the container's
# restart policy brings the whole PLC back.
set -e
export LD_LIBRARY_PATH=/opt/codesys/lib:/opt/codesysedge/lib

# /seed (optional, read-only mount) is copied into the runtime's state dir on a
# fresh volume only: a user database, a boot application, anything that should
# be there before the first login. An existing volume is never overwritten.
if [ -d /seed ] && [ ! -e /var/opt/codesys/.seeded ]; then
    cp -a /seed/. /var/opt/codesys/
    touch /var/opt/codesys/.seeded
fi

# CDS_USER_MGMT=off: no forced user management, so a disposable bench can be
# logged into and downloaded to without first creating an account in the IDE.
if [ "${CDS_USER_MGMT:-on}" = off ]; then
    cfg=/etc/codesyscontrol/CODESYSControl_User.cfg
    # The shipped file has no [CmpUserMgr] section until the runtime first
    # writes one, so add the section ourselves when it is missing.
    if ! grep -q '^SECURITY.UserMgmtEnforce=' "$cfg"; then
        grep -q '^\[CmpUserMgr\]' "$cfg" || printf '\n[CmpUserMgr]\n' >> "$cfg"
        sed -i '/^\[CmpUserMgr\]/a SECURITY.UserMgmtEnforce=NO' "$cfg"
    fi
fi

if [ -x /opt/codesysedge/bin/codesysedge.bin ]; then
    mkdir -p /var/opt/codesysedge
    (cd /var/opt/codesysedge && exec /opt/codesysedge/bin/codesysedge.bin /etc/codesysedge/Gateway.cfg) &
fi
(cd /var/opt/codesys && exec /opt/codesys/bin/codesyscontrol.bin /etc/codesyscontrol/CODESYSControl.cfg) &

trap 'kill $(jobs -p) 2>/dev/null' TERM INT
wait -n
echo "[entrypoint] a process exited, stopping container"
kill $(jobs -p) 2>/dev/null || true
exit 1
