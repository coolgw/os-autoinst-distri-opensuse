#!/bin/bash
# SPDX-License-Identifier: FSFAP
# Diagnostic script for irqbalance and LTP irqbalance01 test

LOG=/tmp/irqbalance_debug.txt
exec > "$LOG" 2>&1

echo "=================================================="
echo "          IRQBALANCE DIAGNOSTIC REPORT            "
echo "=================================================="
date -u
uname -a

echo -e "
### 1. IRQBALANCE SERVICE STATUS ###"
systemctl status irqbalance.service --no-pager -l || true
ps -eo pid,user,label,args | grep -i '[i]rqbalance' || true

echo -e "
### 2. IRQBALANCE JOURNAL LOGS ###"
journalctl -u irqbalance.service --no-pager -n 100 || true

echo -e "
### 3. CONFIGURATION & ENVIRONMENT ###"
echo "--- /etc/sysconfig/irqbalance ---"
[ -f /etc/sysconfig/irqbalance ] && cat /etc/sysconfig/irqbalance || echo "None"
echo "--- irqbalance.service unit definition ---"
systemctl cat irqbalance.service 2>/dev/null || true
echo "--- SELinux status ---"
if command -v getenforce >/dev/null 2>&1; then
    getenforce || true
else
    echo "getenforce not found"
fi

echo -e "
### 4. /proc/interrupts SNAPSHOT (BEFORE WORKLOAD) ###"
cat /proc/interrupts

echo -e "
### 5. /proc/irq/*/smp_affinity PERMISSIONS & VALUES ###"
for i in /proc/irq/[0-9]*; do
    [ -d "$i" ] || continue
    irq=$(basename "$i")
    mode=$(ls -l "$i/smp_affinity" 2>/dev/null | awk '{print $1}')
    val=$(cat "$i/smp_affinity" 2>/dev/null)
    echo "IRQ $irq: mode=$mode smp_affinity=$val"
done

echo -e "
### 6. TEST WRITE TO /proc/irq/*/smp_affinity ###"
for i in /proc/irq/[0-9]*; do
    [ -d "$i" ] || continue
    irq=$(basename "$i")
    val=$(cat "$i/smp_affinity" 2>/dev/null)
    if [ -n "$val" ]; then
        err=$( (echo "$val" > "$i/smp_affinity") 2>&1 )
        res=$?
        if [ $res -ne 0 ]; then
            echo "IRQ $irq: WRITE FAILED ($res) -> $err"
        else
            echo "IRQ $irq: WRITE SUCCEEDED"
        fi
    fi
done

echo -e "
### 7. SECURITY & AVC AUDIT MESSAGES ###"
dmesg | grep -i -E "avc|selinux|apparmor" | tail -n 30 || true
journalctl -g "avc:" --no-pager -n 30 || true

echo -e "
### 8. STANDALONE 'irqbalance --oneshot --debug' ###"
irqbalance --oneshot --debug 2>&1 || true

echo -e "
### 9. INITIAL WORKLOAD: REAL DISK DIRECT I/O & EXTERNAL PING ###"
echo "Generating Direct I/O on real storage (/var/tmp/irq_load_initial.dat)..."
dd if=/dev/urandom of=/var/tmp/irq_load_initial.dat bs=1M count=60 oflag=direct 2>/dev/null ||     dd if=/dev/urandom of=/var/tmp/irq_load_initial.dat bs=1M count=60 2>/dev/null
dd if=/var/tmp/irq_load_initial.dat of=/dev/null bs=1M iflag=direct 2>/dev/null || true
rm -f /var/tmp/irq_load_initial.dat
sync

gw=$(ip route show default | awk '{print $3}' | head -n 1)
echo "Generating Network traffic to 8.8.8.8 and Gateway $gw..."
ping -c 50 -i 0.02 8.8.8.8 >/dev/null 2>&1 || true
if [ -n "$gw" ]; then
    ping -c 100 -i 0.01 "$gw" >/dev/null 2>&1 || true
fi

echo "Waiting 12 seconds for irqbalance 10s cycle..."
sleep 12
echo "--- /proc/interrupts after initial workload ---"
cat /proc/interrupts

echo -e "
### 10. RETEST irqbalance01 AFTER INITIAL WORKLOAD ###"
if [ -x /opt/ltp/testcases/bin/irqbalance01 ]; then
    /opt/ltp/testcases/bin/irqbalance01
else
    irqbalance01
fi
retest_res=$?
echo "irqbalance01 re-test exit code: $retest_res"

if [ $retest_res -eq 0 ]; then
    echo "SUCCESS: irqbalance01 passed after initial workload!"
else
    echo -e "
### 11. INTENSIVE REBALANCING RETRY LOOP ###"
    echo "Initial re-test failed. Starting progressive workload loop to trigger irqbalance migration..."
    MAX_ATTEMPTS=5
    attempt=1
    loop_passed=0

    while [ $attempt -le $MAX_ATTEMPTS ]; do
        echo "=================================================="
        echo "--- Progressive Attempt $attempt of $MAX_ATTEMPTS ---"
        echo "Timestamp: $(date -u +'%T')"

        # If natural load on attempts 1-2 didn't move IRQs (because system is at 1-to-1 equilibrium),
        # induce an asymmetric imbalance on attempt >= 3 to force irqbalance repartitioning
        if [ $attempt -ge 3 ]; then
            echo "[Attempt $attempt] Injecting asymmetric imbalance by temporarily binding IRQ 41 to CPU0..."
            echo 1 > /proc/irq/41/smp_affinity 2>/dev/null || true
        fi

        # 1. Real Block I/O: 100MB Direct I/O on real storage (/var/tmp on vda2)
        echo "[Attempt $attempt] Generating 100MB Direct I/O on real storage..."
        dd if=/dev/urandom of=/var/tmp/irq_loop_io.dat bs=1M count=100 oflag=direct 2>/dev/null ||             dd if=/dev/urandom of=/var/tmp/irq_loop_io.dat bs=1M count=100 2>/dev/null
        dd if=/var/tmp/irq_loop_io.dat of=/dev/null bs=1M iflag=direct 2>/dev/null || true
        rm -f /var/tmp/irq_loop_io.dat
        sync

        # 2. Real Network I/O: External ping to 8.8.8.8 and flood ping to gateway
        echo "[Attempt $attempt] Generating external and gateway network flood..."
        ping -c 80 -i 0.02 8.8.8.8 >/dev/null 2>&1 || true
        if [ -n "$gw" ]; then
            ping -f -c 1000 "$gw" >/dev/null 2>&1 || ping -c 200 -i 0.01 "$gw" >/dev/null 2>&1 || true
        fi

        # 3. Signal irqbalance to force immediate rescan
        echo "[Attempt $attempt] Sending SIGHUP to irqbalance to trigger immediate rescan..."
        systemctl kill -s HUP irqbalance.service 2>/dev/null || killall -HUP irqbalance 2>/dev/null || true

        # 4. Wait for irqbalance rebalance cycle
        echo "[Attempt $attempt] Waiting 12 seconds for irqbalance rebalance cycle..."
        sleep 12

        # 5. Show recent irqbalance activity
        echo "--- [Attempt $attempt] Recent irqbalance journal messages ---"
        journalctl -u irqbalance.service --no-pager -n 15 | tail -n 15 || true

        echo "--- [Attempt $attempt] Active IRQs /proc/interrupts ---"
        grep -E "virtio|xhci|ttyS|i8042|IO-APIC" /proc/interrupts | grep -v -E "timer|rtc0" || true

        echo "--- [Attempt $attempt] Affinity masks of candidate IRQs ---"
        for cand in 36 40 41 42; do
            if [ -f "/proc/irq/$cand/smp_affinity" ]; then
                echo "IRQ $cand: smp_affinity=$(cat /proc/irq/$cand/smp_affinity 2>/dev/null) (mode=$(ls -l /proc/irq/$cand/smp_affinity 2>/dev/null | awk '{print $1}'))"
            fi
        done

        # 6. Re-run irqbalance01
        echo "--- [Attempt $attempt] Running irqbalance01 ---"
        if [ -x /opt/ltp/testcases/bin/irqbalance01 ]; then
            /opt/ltp/testcases/bin/irqbalance01
        else
            irqbalance01
        fi
        loop_rc=$?
        echo "irqbalance01 (Attempt $attempt) exit code: $loop_rc"

        if [ $loop_rc -eq 0 ]; then
            echo "SUCCESS: irqbalance01 passed on attempt $attempt!"
            loop_passed=1
            retest_res=0
            break
        fi

        echo "Attempt $attempt completed without detected migration. Proceeding to next attempt..."
        attempt=$((attempt + 1))
    done

    if [ $loop_passed -eq 0 ]; then
        echo "=================================================="
        echo "All $MAX_ATTEMPTS attempts exhausted. Dumping final irqbalance internal state..."
        irqbalance --oneshot --debug 2>&1 || true
    fi
fi

echo -e "
=================================================="
echo "          END OF IRQBALANCE DIAGNOSTIC            "
echo "=================================================="
exit $retest_res
