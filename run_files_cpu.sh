#!/bin/bash
#SBATCH --job-name=tagging_ollama_cpu
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --cpus-per-task=8
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

export MPLCONFIGDIR=${SLURM_TMPDIR:-/tmp}/mplcache
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false
export PYTHONNOUSERSITE=1

# ---- conda env ----
source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm
export RETICULATE_PYTHON=$(which python)
export RENVIRON_USER=/dev/null

# ---- project ----
cd ~/projects/Mapping_Behav_RL

# ---- Ollama (CPU) via Apptainer ----
cd /rds/projects/z/zhanglp-vwendler-core/
unset APPTAINER_BIND

# persistent model cache on RDS (so pulls persist across jobs)
mkdir -p /rds/projects/z/zhanglp-vwendler-core/ollama_models
mkdir -p ~/.ollama
ln -sfn /rds/projects/z/zhanglp-vwendler-core/ollama_models ~/.ollama/models

# pull container once (stored in project space)
if [ ! -f ollama_latest.sif ]; then
  apptainer pull docker://ollama/ollama
fi

# start Ollama server (CPU)
apptainer exec ollama_latest.sif ollama serve > ollama_server.log 2>&1 &
OLLAMA_PID=$!

# wait for server to be ready
for i in {1..30}; do
  if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# pull a small model suitable for CPU
apptainer exec ollama_latest.sif ollama pull llama2:7b

# run your python tagging script (path below should match where you save it)
cd ~/projects/Mapping_Behav_RL
python Mapping_landscape_ABM/3.1_tags.py

# stop server
kill $OLLAMA_PID
