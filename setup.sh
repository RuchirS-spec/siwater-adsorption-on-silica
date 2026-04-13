#!/usr/bin/env bash
# setup.sh — build LAMMPS+MACE from scratch
# Usage: bash setup.sh
#
# GPU note (WSL2/Windows): MACE full_energy GCMC triggers Windows TDR crashes
# unless you increase the GPU timeout first (run in PowerShell as Admin, then reboot):
#   reg.exe add "HKLM\System\CurrentControlSet\Control\GraphicsDrivers" /v TdrDelay /t REG_DWORD /d 60 /f
#   reg.exe add "HKLM\System\CurrentControlSet\Control\GraphicsDrivers" /v TdrDdiDelay /t REG_DWORD /d 60 /f

set -euo pipefail

WS="$(cd "$(dirname "$0")" && pwd)"
TORCH_VER="2.7.0"
CUDA_VER="cu128"          # change to "cpu" for CPU-only build
NPROC=$(nproc)

echo "==> [1/6] system packages"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    build-essential cmake git wget unzip \
    python3 python3-pip python3-venv

# CUDA toolkit (skip if CPU-only)
if [ "$CUDA_VER" != "cpu" ]; then
    if [ ! -d /usr/local/cuda-12.8 ]; then
        echo "==> installing CUDA 12.8 toolkit"
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
        sudo dpkg -i cuda-keyring_1.1-1_all.deb && rm cuda-keyring_1.1-1_all.deb
        sudo apt-get update -qq
        sudo apt-get install -y cuda-toolkit-12-8
    fi
    CUDA_CMAKE="-DCUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda-12.8"
else
    CUDA_CMAKE=""
fi

# use conda-forge toolchain if conda available (avoids system linker conflicts)
if command -v conda &>/dev/null; then
    echo "==> [2/6] conda-forge toolchain"
    conda install -y -c conda-forge openmpi cxx-compiler fftw
    CMAKE_PREFIX="${WS}/libtorch;${CONDA_PREFIX}"
else
    sudo apt-get install -y --no-install-recommends \
        libopenmpi-dev openmpi-bin libfftw3-dev libblas-dev liblapack-dev
    CMAKE_PREFIX="${WS}/libtorch"
fi

echo "==> [3/6] Python venv"
python3 -m venv "${WS}/.venv"
source "${WS}/.venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet mace-torch

echo "==> [4/6] LibTorch ${TORCH_VER}+${CUDA_VER}"
if [ ! -d "${WS}/libtorch" ]; then
    wget -q --show-progress -O /tmp/libtorch.zip \
        "https://download.pytorch.org/libtorch/${CUDA_VER}/libtorch-cxx11-abi-shared-with-deps-${TORCH_VER}%2B${CUDA_VER}.zip"
    unzip -q /tmp/libtorch.zip -d "${WS}"
    rm /tmp/libtorch.zip
fi

echo "==> [5/6] LAMMPS (ACEsuit mace branch)"
if [ ! -d "${WS}/lammps-mace" ]; then
    git clone --branch mace --depth 1 https://github.com/ACEsuit/lammps.git "${WS}/lammps-mace"
fi

# fix cmake version floor (3.0 removed in cmake 3.28+)
sed -i 's/cmake_minimum_required(VERSION 3\.0/cmake_minimum_required(VERSION 3.5/' \
    "${WS}/lammps-mace/cmake/Modules/Packages/ML-MACE.cmake" 2>/dev/null || true

rm -rf "${WS}/lammps-mace/build"
mkdir "${WS}/lammps-mace/build"
cd "${WS}/lammps-mace/build"

cmake ../cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${CMAKE_PREFIX}" \
    ${CUDA_CMAKE} \
    -DBUILD_MPI=ON -DBUILD_OMP=ON \
    -DPKG_ML-MACE=ON -DPKG_REAXFF=ON \
    -DPKG_MOLECULE=ON -DPKG_MC=ON \
    -DPKG_KSPACE=ON -DPKG_EXTRA-MOLECULE=ON \
    -DPKG_MANYBODY=ON -DPKG_RIGID=ON \
    -DMKL_INCLUDE_DIR=""

make -j"${NPROC}"
cp lmp "${WS}/lmp"
cd "${WS}"

echo "==> [6/6] ReaxFF potential"
if [ ! -f "${WS}/ffield.reax.SiOH" ]; then
    cp "${WS}/lammps-mace/potentials/ffield.reax.SiOH" "${WS}/" 2>/dev/null || \
    wget -q -O "${WS}/ffield.reax.SiOH" \
        "https://www.ctcms.nist.gov/potentials/Download/2010--Fogarty-J-C-Aktulga-H-M-Grama-A-Y-van-Duin-A-C-T-Pandit-S-A--Si-O-H/1/ffield.reax"
fi

echo "==> writing env.sh"
cat > "${WS}/env.sh" << EOF
#!/usr/bin/env bash
WS="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
_LD="\${WS}/libtorch/lib:/usr/local/cuda-12.8/lib64"
[ -n "\${CONDA_PREFIX:-}" ] && _LD="\${_LD}:\${CONDA_PREFIX}/lib"
export LD_LIBRARY_PATH="\${_LD}:\${LD_LIBRARY_PATH:-}"
[ -f "\${WS}/.venv/bin/activate" ] && source "\${WS}/.venv/bin/activate"
EOF
chmod +x "${WS}/env.sh"
chmod +x "${WS}/mace/run.sh" "${WS}/reaxff/run.sh" "${WS}/classical/run.sh"

echo ""
echo "done. to run:"
echo "  source env.sh"
echo "  bash mace/run.sh"
echo "  bash reaxff/run.sh"
echo "  bash classical/run.sh"
