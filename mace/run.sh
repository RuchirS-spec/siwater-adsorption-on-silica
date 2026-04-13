#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source ../env.sh
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128
OMP_NUM_THREADS=4 mpirun -n 1 ../lmp -in gcmc.lmp -log run.log
