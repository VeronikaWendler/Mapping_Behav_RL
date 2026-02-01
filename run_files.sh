#!/bin/bash
#SBATCH --job-name=3_taxonomy.R                   # should be changed to whatever you are running, otherwise confusion 
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=6
#SBATCH --mem=128G
#SBATCH --gres=gpu:1
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=VAW508@student.bham.ac.uk

set -euo pipefail
mkdir -p logs

module purge
module load bear-apps/2024a/live

export HF_HOME=$HOME/.cache/huggingface
unset HF_HUB_OFFLINE
unset TRANSFORMERS_OFFLINE

export MPLCONFIGDIR=${SLURM_TMPDIR:-/tmp}/mplcache
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false

# this is my project folder with code
source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm
cd ~/projects/Mapping_Behav_RL

Rscript Mapping_landscape_ABM/3_taxonomy.R     # or python or Rscript ##

