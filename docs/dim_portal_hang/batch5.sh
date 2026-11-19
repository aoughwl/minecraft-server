#!/bin/sh
cd /c/Users/timbuktu/dev/mcs-v3
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sh docs/dim_portal_hang/driver5.sh off_$i 26500 MC_THREADS=4 MC_CHUNK_WORKERS=4
done
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sh docs/dim_portal_hang/driver5.sh gated_$i 26510 MC_THREADS=4 MC_CHUNK_WORKERS=4 MC_DIM_THREADS=1 MC_DIM_PLAYERS_MULTI_WORLD=1
done
echo DONE >> /c/m3/base/summary.txt
