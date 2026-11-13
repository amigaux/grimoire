#!/bin/sh
# amix-lan-up.sh -- put an Amiberry-emulated Amix guest on the real LAN.
#
# Model: a routed TAP + per-address proxy ARP, NOT an L2 bridge. The host answers
# ARP on the LAN interface ($ETH) for the guest's one address only (an
# `ip neigh ... proxy` entry) and forwards packets to a TAP that Amiberry's
# emulated A2065 attaches to (config line: a2065=tap0). This makes the guest a
# real, reachable host on the LAN *without ever touching the host's own IP /
# default route / NetworkManager* -- so it cannot knock the host off the network.
# (A true L2 bridge also works; see README.md for the trade-off.)
#
# Interface-wide proxy ARP (net.ipv4.conf.$ETH.proxy_arp=1) is deliberately NOT
# used on the LAN side: with it, the host answers ARP for any address it routes
# out of another interface, so a host with two interfaces on one subnet (wired and
# Wi-Fi, say) answers for every address of the LAN and other devices see address
# conflicts. Only the TAP gets interface-wide proxy ARP; it faces just the guest.
#
# ETH: set it (ETH=<wired interface>) for a service. Unset, the script takes the
# default-route interface, and stops instead of guessing when that interface is
# wireless or when another interface also has an address in the guest's subnet.
#
# Idempotent. Run as root (sudo sh amix-lan-up.sh). Tested 2026-06 on Ubuntu-
# family host with Docker present, Amiberry 8.1.6, Amix 2.1 (SVR4.0), with the
# interface-wide LAN-side proxy ARP of that time; the per-address form is not yet
# run on a host.
set -e

GUEST_IP="${GUEST_IP:-192.0.2.38}"          # the guest's LAN address -- the default is an RFC 5737 example: SET GUEST_IP
TAP="${TAP:-tap0}"
TAP_OWNER="${TAP_OWNER:-$(logname 2>/dev/null || echo "$SUDO_USER")}"
TAP_ANCHOR="${TAP_ANCHOR:-192.0.2.17}"      # host-side /32 on the tap (host<->guest); SET it to an address unused on your LAN

die() { echo "amix-lan: $*" >&2; exit 1; }

# Interfaces other than the TAP with an IPv4 address whose subnet holds GUEST_IP.
subnet_ifaces() {
    ip -o -4 addr show scope global 2>/dev/null | awk -v g="$GUEST_IP" -v tap="$TAP" '
        function n(a,  p) { split(a, p, "."); return ((p[1] * 256 + p[2]) * 256 + p[3]) * 256 + p[4] }
        $2 != tap && $3 == "inet" {
            split($4, c, "/"); size = 2 ^ (32 - c[2])
            if (int(n(c[1]) / size) == int(n(g) / size)) print $2
        }' | sort -u
}
is_wireless() { [ -d "/sys/class/net/$1/wireless" ] || [ -e "/sys/class/net/$1/phy80211" ]; }

# LAN uplink: ETH when set; otherwise the default-route interface, if that is safe.
if [ -z "${ETH:-}" ]; then
    ETH="$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')"
    [ -n "$ETH" ] || die "cannot determine the LAN interface; set ETH=<wired interface>"
    IN_SUBNET="$(subnet_ifaces | tr '\n' ' ' | sed 's/ $//')"
    # shellcheck disable=SC2086  # split the interface list into $1, $2, ...
    set -- $IN_SUBNET
    if [ $# -gt 1 ]; then
        die "several interfaces have an address in $GUEST_IP's subnet ($IN_SUBNET); set ETH=<wired interface>"
    fi
    if [ $# -eq 1 ] && [ "$1" != "$ETH" ]; then
        die "$GUEST_IP's subnet is on $1, the default route on $ETH; set ETH=<wired interface>"
    fi
    if is_wireless "$ETH"; then
        die "the default-route interface $ETH is wireless; set ETH=<wired interface>"
    fi
    [ $# -eq 1 ] || echo "amix-lan: warning: no interface has an address in $GUEST_IP's subnet; using $ETH" >&2
fi
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
# That is not reproduced guest to guest on 2026-11-05 on Amiberry 1621e26 (on branch
# amix-v842 of the amiberry fork), with two guests on bridged taps at 1500: ftp of
# 8.4 MB each way at a mean of ~1507 bytes per frame,
# and NFS 8 KiB reads and writes of 16-24 MiB, completed with no stall. With those
# taps at 1400, pings of 1400 data bytes and up between the guests got no reply, and
# an 8 KiB soft-mount NFS read failed with `Bad address`. The first soft-mount write
# of a measurement failed twice, once at each MTU, unexplained; 8 later writes did not.
#
# Guest to host, a full-size ICMP echo (1472 data bytes, 3 packets) got replies even
# with a tap at 1400, so the guest's full frame reached the host. The likely reason,
# inferred with no capture, is that a tap's MTU limits frames going out to the guest,
# not what the guest writes in.
#
# Not measured yet: TCP guest to host at MSS 1460, single frames above 1400 from host
# to guest, this LAN tap above 1400, which Amiberry commit changed the behaviour, and
# real hardware. So the default stays until then.
# On the guest, `ifconfig aen0 mtu 1400` is refused (`mtu: bad value`); other forms
# of that command are untested.
ip link set "$TAP" mtu "${TAP_MTU:-1400}"
ip addr replace "$TAP_ANCHOR/32" dev "$TAP"

# 2. Route the guest's /32 out the tap, with a same-subnet source address so the
#    host itself can originate traffic to the guest (ping/telnet/ftp from host).
ip route replace "$GUEST_IP/32" dev "$TAP" src "$TAP_ANCHOR"

# 3. Proxy ARP. LAN side: answer for the guest's address only, on $ETH only;
#    any entry for it left on another interface is removed, so exactly one
#    interface answers. Tap side: interface-wide, so the guest's ARP for the
#    gateway and other LAN hosts gets the host's answer. ip_forward lets the
#    host route between the two.
sysctl -wq net.ipv4.ip_forward=1
ip -4 neigh show proxy 2>/dev/null | awk -v g="$GUEST_IP" -v e="$ETH" '$1 == g && $2 == "dev" && $3 != e { print $3 }' |
    while read -r OLD; do ip neigh del proxy "$GUEST_IP" dev "$OLD" 2>/dev/null || true; done
ip neigh replace proxy "$GUEST_IP" dev "$ETH"
sysctl -wq "net.ipv4.conf.$TAP.proxy_arp=1"
if [ "$(cat "/proc/sys/net/ipv4/conf/$ETH/proxy_arp" 2>/dev/null)" = 1 ]; then
    echo "amix-lan: warning: interface-wide proxy_arp is on for $ETH (an older amix-lan-up.sh, or set" >&2
    echo "amix-lan:   elsewhere); it is not needed now, and amix-lan-down.sh clears it" >&2
fi

# 4. Permit forwarding even when Docker has set the FORWARD policy to DROP.
#    DOCKER-USER is evaluated before Docker's own rules and is never flushed by
#    Docker, so it is the durable place for these ACCEPTs. Fall back to FORWARD.
if iptables -t filter -L DOCKER-USER >/dev/null 2>&1; then CHAIN=DOCKER-USER; else CHAIN=FORWARD; fi
add_rule() { iptables -C "$CHAIN" "$@" 2>/dev/null || iptables -I "$CHAIN" 1 "$@"; }
add_rule -i "$TAP" -o "$ETH" -j ACCEPT
add_rule -i "$ETH" -o "$TAP" -j ACCEPT

echo "[amix-lan] up. Now start Amiberry with a2065=$TAP (see README.md / amix_net.uae)."
echo "[amix-lan] In the guest, aen0 auto-configures from /etc/inet/hosts at boot."
