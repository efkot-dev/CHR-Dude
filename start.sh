#!/bin/sh
set -e

MEM="${MEM:=512m}"
DISK="${DISK:=128M}"
CPUS="${CPUS:=1}"
bridge_index=0

get_mac_address() {
    ifname="$1"
    ip link show "$ifname" 2>/dev/null | awk '/link\/ether/ {print $2}'
}

increment_mac() {
    mac=$1
    mac_no_colons=$(echo "$mac" | tr -d ':' | tr '[:lower:]' '[:upper:]')
    mac_dec=$((16#${mac_no_colons}))
    mac_dec=$((mac_dec + 1))
    mac_hex=$(printf "%012X" "$mac_dec")
    echo "$mac_hex" | sed 's/.\{2\}/&:/g;s/:$//'
}

echo "" > /etc/qemu/bridge.conf

qemu="qemu-system-x86_64"
if [[ `uname -m` == "aarch64" ]]; then
   qemu="qemu-system-aarch64 -pflash /usr/share/qemu/edk2-aarch64-code.fd -M virt"
fi

if [ -e /dev/kvm ]; then
    qemu="$qemu -enable-kvm -cpu host"
else
    if [[ `uname -m` == "aarch64" ]]; then
        qemu="$qemu -cpu cortex-a57"
    fi
fi

img=`ls /diskimage/*.img`
qemu="$qemu -nographic -m $MEM -smp cpus=$CPUS -drive file=$img,format=raw"
truncate -s $DISK $img

while read -r line; do
    iface=$(echo "$line" | sed "s/ *\([a-z0-9]*\):.*/\1/")
    if [[ "$iface" =~ " " ]]; then
        continue
    fi
    if [[ "$iface" =~ ^br ]]; then
        continue
    fi
    if [[ "$iface" == "lo" ]]; then
        continue
    fi
    if [[ "$iface" == "" ]]; then
        continue
    fi
    echo "iface: $iface"
    bridge="br$bridge_index"
    ip link add name "$bridge" type bridge
    ip link set dev "$bridge" up
    ip link set "$iface" master "$bridge"
    echo "allow $bridge" >> /etc/qemu/bridge.conf

    veth_mac=$(get_mac_address "$iface")
    tap_mac=$(increment_mac "$veth_mac")

    bridge_index=$((bridge_index + 1))
    qemu="$qemu -netdev bridge,id=$bridge,br=$bridge -device virtio-net,netdev=$br
idge,mac=$tap_mac "
done < /proc/net/dev

echo "qemu: $qemu"
exec $qemu
