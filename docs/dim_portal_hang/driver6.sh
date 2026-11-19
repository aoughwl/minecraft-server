#!/bin/sh
# usage: driver6.sh TAG PORT ENV=... ; one dim_portal run with DIM_PORTAL_TRACE=1, exe C:/m3/pr.exe, out C:/m3/pr/TAG
TAG=$1; PORT=$2; shift 2
cd /c/Users/timbuktu/dev/mcs-pr
D=C:/m3/pr/$TAG
env "$@" DIM_PORTAL_TRACE=1 SCENARIO_DIR=$D PORT=$PORT sh tools/run_dim_portal.sh C:/m3/pr.exe > /c/m3/pr/$TAG.out 2>&1
echo "rc=$? $TAG fail: $(grep -h -i -m2 'not a nether_portal\|timed out' $D/botA.txt | tr '\n' '|' | cut -c1-200) ids: $(grep -h 'state ids' $D/botA.txt)" >> /c/m3/pr/summary.txt
