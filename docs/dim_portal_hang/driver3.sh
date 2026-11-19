#!/bin/sh
TAG=$1; PORT=$2; shift 2
cd /c/Users/timbuktu/dev/mcs-v3
D=C:/m3/wake/$TAG
free=$(powershell -NoProfile -Command "[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB,1)" | tr -d '\r')
echo "### $TAG port=$PORT free=$free $(date +%T) env=$*" >> /c/m3/wake/summary3.txt
env "$@" SCENARIO_DIR=$D PORT=$PORT sh tools/run_dim_portal.sh C:/m/int_wake.exe > /c/m3/wake/$TAG.out 2>&1 &
RP=$!
dumped=0
while kill -0 $RP 2>/dev/null; do
  sleep 4
  [ -f $D/botA.txt ] && [ -f $D/botB.txt ] || continue
  now=$(date +%s)
  ma=$(stat -c %Y $D/botA.txt); mb=$(stat -c %Y $D/botB.txt)
  if [ $((now-ma)) -ge 40 ] && [ $((now-mb)) -ge 40 ] && [ $dumped = 0 ]; then
    pid=$(netstat -ano | grep -E "UDP +0.0.0.0:$((PORT+2)) " | head -1 | awk '{print $NF}')
    [ -n "$pid" ] || continue
    echo "HANG: bots quiet; pid=$pid; dumping $(date +%T)" >> /c/m3/wake/summary3.txt
    gdb -p $pid -batch -ex "thread apply all bt 25" -ex detach > $D.hang.txt 2>&1
    dumped=1
  fi
done
wait $RP; rc=$?
echo "rc=$rc $TAG hang=$dumped $(grep -c 'SERVER NOT ANSWERING' /c/m3/wake/$TAG.out) $(grep -m1 -o 'timed out[^"]*' /c/m3/wake/$TAG.out | head -1) $(date +%T)" >> /c/m3/wake/summary3.txt
