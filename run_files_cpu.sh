#!/bin/bash
#SBATCH --job-name=sem_taxonomy_openai
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --qos=bbdefault
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x.%j.out
#SBATCH --error=logs/%x.%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=VAW508@student.bham.ac.uk

set -euo pipefail
mkdir -p logs

module purge
module load bear-apps/2024a/live

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

export OPENAI_API_KEY="$(cat /rds/projects/z/zhanglp-vwendler-core/SECRETS/openai_api_key.txt)"
export OPENAI_MODEL="gpt-4.1-mini"              
export OPENAI_URL="https://api.openai.com/v1/chat/completions"

export MAX_PAIRS=15000
export BATCH_SIZE=100
export TIMEOUT=120
export RETRIES=6
unset FORCE_START

export PYTHONPATH="/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/py_pkgs:${PYTHONPATH:-}"
cd ~/projects/Mapping_Behav_RL
Rscript Mapping_landscape_ABM/3_taxonomy.R