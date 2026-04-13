#!/bin/bash
set -eo pipefail
unset CONDA_BACKUP_ADDR2LINE ADDR2LINE

ENV="silica-water-test-env"
echo "[1/5] Setting up conda env..."
command -v conda >/dev/null || { echo "conda not found"; exit 1; }

if ! conda env list | grep -q "^$ENV "; then
    conda create -y -n "$ENV" python=3.11
fi
eval "$(conda shell.bash hook)"
conda activate "$ENV"

echo "[2/5] Installing build deps..."
conda install -y -c conda-forge cmake cxx-compiler mkl-devel fftw \
    pkg-config openmpi binutils_linux-64 git

echo "[3/5] Installing PyTorch + MACE..."
pip install --upgrade pip
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install mace-torch

echo "[4/5] Building LAMMPS with ML-MACE..."
BUILD="/tmp/lammps-mace-build"
rm -rf "$BUILD"
git clone --depth=1 -b mace https://github.com/ACEsuit/lammps.git "$BUILD/src"
TORCH_CMAKE=$(python -c "import torch, os; print(os.path.join(torch.__path__[0],'share','cmake'))")

mkdir -p "$BUILD/build"
cd "$BUILD/build"
cmake ../src/cmake \
    -D PKG_ML-MACE=ON \
    -D PKG_REAXFF=ON \
    -D CMAKE_PREFIX_PATH="$TORCH_CMAKE;$CONDA_PREFIX" \
    -D CMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
    -D USE_CUDA=OFF \
    -D CMAKE_BUILD_TYPE=Release 2>&1 | tee cmake.log

echo "  cmake done, starting make (this takes 20-60 min, watch make.log)..."
make -j"$(nproc)" 2>&1 | tee make.log
make install

echo "[5/5] Verifying..."
lmp -help 2>&1 | grep -i mace && echo "ML-MACE: OK" || echo "WARNING: ML-MACE not found in lmp"

mkdir -p results/trajectories results/outputs
echo "Done. Run: conda activate $ENV"
