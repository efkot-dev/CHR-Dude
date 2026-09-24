#!/bin/sh
set -e

MEM="${MEM:=512m}"
DISK="${DISK:=128M}"
CPUS="${CPUS:=1}"
MACHINE="${MACHINE:=q35}"   # q35 | pc

# --- параметры виртуального диска (переопределяются через env контейнера) ---
CACHE="${CACHE:=none}"        # none | writeback | writethrough | unsafe
AIO="${AIO:=native}"          # native | threads | io_uring
IOTHREAD="${IOTHREAD:=yes}"   # yes | no
DISCARD="${DISCARD:=off}"     # on | off

# native и io_uring работают только с cache=none, иначе принудительно threads
if [ "$CACHE" != "none" ]; then
    AIO="threads"
fi
# ----------------------------------------------------------------------------

bridge_index=0

get_mac_address() {
    ifname="$1"
    ip link show "$ifname" 2>/dev/null | awk '/link\/ether/ {print $2}'
}

increment_mac() {
    mac=$1
    mac_no_colons=$(echo "$mac" | tr -d ':' | tr '[:upper:]' '[:lower:]')
    mac_dec=$((16#${mac_no_colons}))
    mac_dec=$((mac_dec + 1))
    mac_hex=$(printf "%012x" "$mac_dec")
    echo "$mac_hex" | sed 's/.\{2\}/&:/g;s/:$//'
}

echo "" > /etc/qemu/bridge.conf

qemu="qemu-system-x86_64 -machine $MACHINE"

if [ -e /dev/kvm ]; then
    qemu="$qemu -enable-kvm -cpu host"
fi

img=`ls diskimage/*.img`
qemu="$qemu -nographic -m $MEM -smp cpus=$CPUS -drive file=$img,format=raw,if=none,id=d0,cache=$CACHE,aio=$AIO,discard=$DISCARD"

truncate -s $DISK $img

if [ "$IOTHREAD" = "yes" ]; then
    qemu="$qemu -object iothread,id=io0 -device virtio-blk-pci,drive=d0,iothread=io0"
else
    qemu="$qemu -device virtio-blk-pci,drive=d0"
fi

while read -r line; do
    iface=$(echo "$line" | sed "s/ *\([a-z0-9]*\):.*/\1/")
    if [[ "$iface" =~ " " ]] || [[ "$iface" =~ ^br ]] || [[ "$iface" == "lo" ]] || [[ "$iface" == "" ]]; then
        continue
    fi
    echo "iface: $iface"
    bridge="br$bridge_index"
    if ! ip link show "$bridge" >/dev/null 2>&1; then
        ip link add name "$bridge" type bridge
    fi
    ip link set dev "$bridge" up
    ip link set "$iface" master "$bridge"
    echo "allow $bridge" >> /etc/qemu/bridge.conf

    veth_mac=$(get_mac_address "$iface")
    tap_mac=$(increment_mac "$veth_mac")

    bridge_index=$((bridge_index + 1))
    qemu="$qemu -netdev bridge,id=$bridge,br=$bridge -device virtio-net-pci,netdev=$bridge,mac=$tap_mac"
done < /proc/net/dev

echo "qemu: $qemu"
exec $qemu
