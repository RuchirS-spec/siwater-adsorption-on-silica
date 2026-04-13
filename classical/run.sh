#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ../env.sh
OMP_NUM_THREADS=10 mpirun -n 1 ../lmp -in gcmc.lmp -log run.log -screen none
