#!/bin/bash
#SBATCH --job-name=1000_semantic_net_
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --cpus-per-task=32
#SBATCH --mem=200G
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

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

# ---- Ollama model cache on RDS (so you don't re-download every job)
mkdir -p /rds/projects/z/zhanglp-vwendler-core/ollama_models
mkdir -p ~/.ollama
ln -sfn /rds/projects/z/zhanglp-vwendler-core/ollama_models ~/.ollama/models

# ---- Pull container once
if [ ! -f ollama_latest.sif ]; then
  apptainer pull ollama_latest.sif docker://ollama/ollama
fi

# ---- Start Ollama (CPU; NO --nv)
apptainer exec ollama_latest.sif ollama serve > ollama_server.log 2>&1 &
OLLAMA_PID=$!

cleanup() { kill $OLLAMA_PID 2>/dev/null || true; }
trap cleanup EXIT

# ---- Wait until ready
for i in {1..60}; do
  if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "[FATAL] Ollama server did not start." >&2
  tail -n 120 ollama_server.log || true
  exit 1
fi

# ---- Pull model only if missing
MODEL="llama2:7b"
if ! apptainer exec ollama_latest.sif ollama list | awk '{print $1}' | grep -qx "$MODEL"; then
  apptainer exec ollama_latest.sif ollama pull "$MODEL"
fi

# ---- Runtime knobs for your Python script (important)
export OLLAMA_MODEL="llama2:7b"
export OLLAMA_THREADS="${SLURM_CPUS_PER_TASK}"
export OLLAMA_WORKERS=1
export BATCH_SIZE=20
export OLLAMA_TIMEOUT=1800
export OLLAMA_RETRIES=2

# If your modified script supports these (recommended):
export MAX_PAIRS=50000
export OLLAMA_NUM_PREDICT=32
export OLLAMA_NUM_CTX=2048

cd ~/projects/Mapping_Behav_RL
python Mapping_landscape_ABM/22.1_semantic_ratings.py