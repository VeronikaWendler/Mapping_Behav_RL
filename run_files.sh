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

BB_WORKDIR=$(mktemp -d /scratch/${USER}_${SLURM_JOBID}.XXXXXX)
export TMPDIR=${BB_WORKDIR}

export HF_HOME=${BB_WORKDIR}/hf
export HF_DATASETS_CACHE=${HF_HOME}/datasets
export TORCH_HOME=${HF_HOME}/torch
export XDG_CACHE_HOME=${BB_WORKDIR}/xdg
export MPLCONFIGDIR=${BB_WORKDIR}/mplcache

export PIP_CACHE_DIR=${BB_WORKDIR}/pip
export CONDA_PKGS_DIRS=${BB_WORKDIR}/conda_pkgs
export NUMBA_CACHE_DIR=${BB_WORKDIR}/numba
export JOBLIB_TEMP_FOLDER=${BB_WORKDIR}/joblib

mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE" "$TORCH_HOME" "$XDG_CACHE_HOME" \
         "$PIP_CACHE_DIR" "$CONDA_PKGS_DIRS" "$NUMBA_CACHE_DIR" "$JOBLIB_TEMP_FOLDER" \
         "$MPLCONFIGDIR"

unset TRANSFORMERS_CACHE
unset HF_HUB_CACHE
export TOKENIZERS_PARALLELISM=false
export PYTHONUNBUFFERED=1

export OUTDIR=${BB_WORKDIR}/outputs
mkdir -p "$OUTDIR"

Rscript Mapping_landscape_ABM/1_clean_abstracts.R

# results back to RDS
cp -v "${OUTDIR}"/*  ~/projects/Mapping_Behav_RL/Mapping_landscape_ABM/Data/ || true

rm -rf "${BB_WORKDIR}"






