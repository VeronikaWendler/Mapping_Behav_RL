#!/bin/bash
#SBATCH --job-name=map_filter
#SBATCH --time=24:00:00
#SBATCH --mem=64G
#SBATCH --mem=180G
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=vaw508@bham.ac.uk

set -euo pipefail
mkdir -p logs

module purge
module load R

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

export HF_HOME=$HOME/.cache/huggingface
export TRANSFORMERS_CACHE=$HOME/.cache/huggingface
export MPLCONFIGDIR=${SLURM_TMPDIR:-/tmp}/mplcache
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false

cd ~/projects/Mapping_Behav_RL

Rscript Mapping_landscape_ABM/1_filter.R