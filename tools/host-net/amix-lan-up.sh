#!/bin/sh
# amix-lan-up.sh -- put an Amiberry-emulated Amix guest on the real LAN.
#
# Model: a routed TAP + proxy-ARP, NOT an L2 bridge. The host answers ARP for
# the guest's reserved IP on the LAN side and forwards packets to a TAP that
# Amiberry's emulated A2065 attaches to (config line: a2065=tap0). This makes
# the guest a real, reachable host on the LAN *without ever touching the host's
# own IP / default route / NetworkManager* -- so it cannot knock the host off
# the network. (A true L2 bridge also works; see README.md for the trade-off.)
#
# Idempotent. Run as root (sudo sh amix-lan-up.sh). Tested 2026-06 on Ubuntu-
# family host with Docker present, Amiberry 8.1.6, Amix 2.1 (SVR4.0).
set -e

GUEST_IP="${GUEST_IP:-192.0.2.38}"          # the guest's LAN address -- the default is an RFC 5737 example: SET GUEST_IP
TAP="${TAP:-tap0}"
TAP_OWNER="${TAP_OWNER:-$(logname 2>/dev/null || echo "$SUDO_USER")}"
TAP_ANCHOR="${TAP_ANCHOR:-192.0.2.17}"      # host-side /32 on the tap (host<->guest); SET it to an address unused on your LAN
# LAN uplink = the interface carrying the default route, unless overridden.
ETH="${ETH:-$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')}"

[ -n "$ETH" ] || { echo "amix-lan: cannot determine LAN interface; set ETH=..." >&2; exit 1; }
echo "[amix-lan] guest=$GUEST_IP tap=$TAP eth=$ETH owner=${TAP_OWNER:-root} anchor=$TAP_ANCHOR"

# 1. Persistent, user-owned TAP. Amiberry attaches to it via TUNSETIFF
#    (a2065=tap0) -- this needs NO cap_net_admin and uses /dev/net/tun, not
#    libpcap, which is what makes it work where pcap-bridged setups are blocked.
if ! ip link show "$TAP" >/dev/null 2>&1; then
    if [ -n "$TAP_OWNER" ]; then
        ip tuntap add dev "$TAP" mode tap user "$TAP_OWNER"
    else
        ip tuntap add dev "$TAP" mode tap
    fi
fi
ip link set "$TAP" up
# Cap the tap MTU so the host advertises a smaller TCP MSS to the guest. 1400 comes
# from an earlier Amiberry, measured 2026-06-22: bulk transfers off the box (ftp GET,
# large writes) stalled at ~4 KB while small transfers and host->guest pushes worked,
# and a 1.5 MB GET went from 0 bytes to a full transfer once mtu <= 1450. It was read
# then as the emulated A2065 dropping full ~1500-byte frames on TX.
#
# That is not reproduced guest to guest on the Amiberry of 2026-11-05, with two guests
# on bridged taps at 1500: ftp of 8.4 MB each way at a mean of ~1507 bytes per frame,
# and NFS 8 KiB reads and writes of 16-24 MiB, completed with no stall. With those
# taps at 1400, pings of 1400 data bytes and up between the guests got no reply, and
# an 8 KiB soft-mount NFS read failed with `Bad address`.
#
# Not measured yet: guest to host above 1400, this LAN tap above 1400, which Amiberry
# commit changed the behaviour, and real hardware. So the default stays until then.
# On the guest, `ifconfig aen0 mtu 1400` is refused (`mtu: bad value`); other forms
# of that command are untested.
ip link set "$TAP" mtu "${TAP_MTU:-1400}"
ip addr replace "$TAP_ANCHOR/32" dev "$TAP"

# 2. Route the guest's /32 out the tap, with a same-subnet source address so the
#    host itself can originate traffic to the guest (ping/telnet/ftp from host).
ip route replace "$GUEST_IP/32" dev "$TAP" src "$TAP_ANCHOR"

# 3. Make the host a proxy-ARP router between the tap and the LAN.
sysctl -wq net.ipv4.ip_forward=1
sysctl -wq "net.ipv4.conf.$ETH.proxy_arp=1"
sysctl -wq "net.ipv4.conf.$TAP.proxy_arp=1"

# 4. Permit forwarding even when Docker has set the FORWARD policy to DROP.
#    DOCKER-USER is evaluated before Docker's own rules and is never flushed by
#    Docker, so it is the durable place for these ACCEPTs. Fall back to FORWARD.
if iptables -t filter -L DOCKER-USER >/dev/null 2>&1; then CHAIN=DOCKER-USER; else CHAIN=FORWARD; fi
add_rule() { iptables -C "$CHAIN" "$@" 2>/dev/null || iptables -I "$CHAIN" 1 "$@"; }
add_rule -i "$TAP" -o "$ETH" -j ACCEPT
add_rule -i "$ETH" -o "$TAP" -j ACCEPT

echo "[amix-lan] up. Now start Amiberry with a2065=$TAP (see README.md / amix_net.uae)."
echo "[amix-lan] In the guest, aen0 auto-configures from /etc/inet/hosts at boot."
