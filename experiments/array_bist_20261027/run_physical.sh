#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 ]] || { echo 'usage: run_physical.sh diag|array SHA256'; exit 2; }
mode=$1;expected=$2
[[ $mode == diag || $mode == array ]]
[[ $expected =~ ^[a-f0-9]{64}$ ]]
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target=0000:84:00.0
reference=/root/fpga/DynamicStream-HLS/phase1/matrix_v1/phase1_matrix_engine_v1.bit
[[ $(id -u) == 0 ]]
[[ $(cat /sys/bus/pci/devices/$target/vendor) == 0x10ee ]]
[[ $(cat /sys/bus/pci/devices/$target/device) == 0x9038 ]]
[[ $(cat /sys/bus/pci/devices/$target/subsystem_device) == 0xeec6 ]]
echo "$expected  $base/$mode.bit" | sha256sum -c -
echo "59358c612a7075ce1c8433ef26fe9bf4d5a7d30defdf501579195ce9baf2b984  $reference" | sha256sum -c -
exec 9>/tmp/xiyuan_bringup_84_00_0.lock;flock -n 9
exec 8>/tmp/dynamicstream_phase1_card0.lock;flock -n 8
run=$(mktemp -d "$base/run-$mode-$(date +%Y%m%d-%H%M%S)-XXXXXX")
mkdir "$run/dev"
restore=0
cleanup(){
    rc=$?;trap - EXIT;set +e
    if [[ $restore == 1 ]]; then
        timeout --kill-after=5s 90s "$run/program_volatile" "$run/dev/user" "$run/dev/h2c_0" "$run/dev/c2h_0" "$reference" > "$run/restore_reference.log" 2>&1
        rr=$?
        if [[ $rr == 0 ]]; then
            "$run/post_program_reset" "$run/dev/user" >> "$run/restore_reference.log" 2>&1;rr=$?
        fi
        if [[ $rr == 0 ]]; then
            /root/fpga/xiyuan_midterm_20261027/debug2/dma_probe read "$run/dev/c2h_0" 0x20d0000020 4 "$run/reference_status.bin" >> "$run/restore_reference.log" 2>&1
            rr=$?
        fi
        if [[ $rr == 0 ]]; then echo REFERENCE_RESTORED;else echo REFERENCE_RESTORE_FAILED;rc=30;fi
    fi
    for node in "$run"/dev/*; do [[ ! -c $node ]] || unlink "$node"; done
    echo "FINAL_EXIT=$rc"
    exit "$rc"
}
trap cleanup EXIT
exec > >(tee "$run/run.log") 2>&1
printf 'RUN_DIRECTORY=%s\nTARGET_PCI=%s\n' "$run" "$target"
name=$(find /sys/bus/pci/devices/$target/xdma -maxdepth 1 -name '*_user' -printf '%f')
[[ $name =~ ^xdma[0-9]+_user$ ]];xid=${name%_user}
for kind in user control h2c_0 c2h_0 h2c_1 c2h_1 h2c_2 c2h_2 h2c_3 c2h_3; do
    pair=$(cat /sys/class/xdma/${xid}_$kind/dev)
    mknod "$run/dev/$kind" c "${pair%:*}" "${pair#*:}";chmod 600 "$run/dev/$kind"
done
if fuser "$run"/dev/*; then echo TARGET_IN_USE_STOP;exit 4;fi
gcc -O2 -Wall -Wextra -Werror "$base/program_volatile.c" -o "$run/program_volatile"
gcc -O2 -Wall -Wextra -Werror "$base/sample_done.c" -o "$run/sample_done"
gcc -O2 -Wall -Wextra -Werror "$base/post_program_reset.c" -o "$run/post_program_reset"
restore=1
timeout --kill-after=5s 90s "$run/program_volatile" "$run/dev/user" "$run/dev/h2c_0" "$run/dev/c2h_0" "$base/$mode.bit"
timeout --kill-after=5s 50s "$run/sample_done" "$run/dev/user" 40 "$run/done_samples.csv"
PYTHONDONTWRITEBYTECODE=1 /home/test/miniconda3/bin/python3.13 "$base/verify_capture.py" "$run/done_samples.csv" --mode "$mode" --checksum 0x1f41
echo AUTONOMOUS_PHYSICAL_CAPTURE_PASS
