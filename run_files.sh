#!/bin/bash
#SBATCH --job-name=3_taxonomy.R
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=6
#SBATCH --mem=128G
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=VAW508@student.bham.ac.uk

set -euo pipefail
mkdir -p logs

module purge
module load bear-apps/2024a/live
module load GCC/13.3.0
module load R/4.5.0-gfbf-2024a

cd ~/projects/Mapping_Behav_RL

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

# HuggingFace cache
export HF_HOME=/rds/homes/v/vaw508/projects/Mapping_Behav_RL/hf_cache
export HF_DATASETS_CACHE=$HF_HOME/datasets
export TORCH_HOME=$HF_HOME/torch

mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE" "$TORCH_HOME"

unset TRANSFORMERS_CACHE
unset HF_HUB_CACHE

# temp files 
export TMPDIR=/rds/homes/v/vaw508/projects/Mapping_Behav_RL/tmp
mkdir -p "$TMPDIR"

# OpenSSL
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
export LD_PRELOAD="$CONDA_PREFIX/lib/libcrypto.so.3:$CONDA_PREFIX/lib/libssl.so.3"

# allow downloads
export HF_HUB_OFFLINE=0
export TRANSFORMERS_OFFLINE=0

export MPLCONFIGDIR=${TMPDIR}/mplcache
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false

Rscript Mapping_landscape_ABM/3_taxonomy.R
