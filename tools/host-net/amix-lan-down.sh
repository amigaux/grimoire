#!/bin/sh
# amix-lan-down.sh -- tear down everything amix-lan-up.sh created. Idempotent.
# Does NOT touch the host's own IP/route (the routed-TAP model never changed them).
#
# It finds the LAN interface from what amix-lan-up.sh left (the guest's proxy
# entry and the forward rules), so ETH need not be set. On each such interface it
# also clears an interface-wide proxy_arp=1, which older versions of
# amix-lan-up.sh set and the per-address model no longer uses.
GUEST_IP="${GUEST_IP:-192.0.2.38}"   # RFC 5737 example default: set GUEST_IP
TAP="${TAP:-tap0}"

# The LAN interfaces: ETH if set, any holding a proxy entry for the guest, and
# the other side of any forward rule for the TAP.
LANS="$({
    [ -n "${ETH:-}" ] && echo "$ETH"
    ip -4 neigh show proxy 2>/dev/null | awk -v g="$GUEST_IP" '$1 == g && $2 == "dev" { print $3 }'
    for CHAIN in DOCKER-USER FORWARD; do
        iptables -S "$CHAIN" 2>/dev/null | awk -v t="$TAP" '
            $1 == "-A" && $3 == "-i" && $5 == "-o" && $7 == "-j" && $8 == "ACCEPT" && NF == 8 {
                if ($4 == t) print $6; else if ($6 == t) print $4 }'
    done
} | sort -u)"

ip route del "$GUEST_IP/32" dev "$TAP" 2>/dev/null || true
for LAN in $LANS; do
    ip neigh del proxy "$GUEST_IP" dev "$LAN" 2>/dev/null || true
    for CHAIN in DOCKER-USER FORWARD; do
        iptables -D "$CHAIN" -i "$TAP" -o "$LAN" -j ACCEPT 2>/dev/null || true
        iptables -D "$CHAIN" -i "$LAN" -o "$TAP" -j ACCEPT 2>/dev/null || true
    done
    if [ "$(cat "/proc/sys/net/ipv4/conf/$LAN/proxy_arp" 2>/dev/null)" = 1 ]; then
        sysctl -wq "net.ipv4.conf.$LAN.proxy_arp=0" 2>/dev/null &&
            echo "[amix-lan] cleared interface-wide proxy_arp on $LAN"
    fi
done
ip link del "$TAP" 2>/dev/null || true
# ip_forward is left as-is (Docker and others rely on it).
echo "[amix-lan] down."
