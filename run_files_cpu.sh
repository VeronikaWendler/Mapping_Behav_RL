#!/bin/bash
#SBATCH --job-name=1000_semantic_net_
#SBATCH --account=zhanglp-vwendler-core
#SBATCH --qos=bbdefault
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

# ----------------------------
# Big, persistent space for Apptainer build/unpack + cache
# (avoids HOME quota AND /tmp "no space left on device")
# ----------------------------
export APPTAINER_TMPDIR="/rds/projects/z/zhanglp-vwendler-core/apptainer_tmp"
export APPTAINER_CACHEDIR="/rds/projects/z/zhanglp-vwendler-core/apptainer_cache"
mkdir -p "$APPTAINER_TMPDIR" "$APPTAINER_CACHEDIR"

# Keep matplotlib/python caches off HOME
export MPLCONFIGDIR="${SLURM_TMPDIR:-/tmp}/mplcache"
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false
export PYTHONNOUSERSITE=1

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

# ----------------------------
# Ollama models: FORCE RDS path (no ~/.ollama symlinks needed)
# ----------------------------
export OLLAMA_MODELS="/rds/projects/z/zhanglp-vwendler-core/ollama_models"
mkdir -p "$OLLAMA_MODELS"

echo "[INFO] OLLAMA_MODELS=$OLLAMA_MODELS"
ls -ld "$OLLAMA_MODELS" || true

# ----------------------------
# Store the Ollama container SIF on RDS (pull once)
# ----------------------------
CONTAINERS_DIR="/rds/projects/z/zhanglp-vwendler-core/containers"
SIF="${CONTAINERS_DIR}/ollama_latest.sif"
mkdir -p "$CONTAINERS_DIR"

if [ ! -f "$SIF" ]; then
  echo "[INFO] Pulling Ollama container to: $SIF"
  apptainer pull "$SIF" docker://ollama/ollama
else
  echo "[INFO] Using existing container: $SIF"
fi

# ----------------------------
# Start Ollama (CPU mode; do NOT use --nv)
# ----------------------------
LOG="ollama_server.${SLURM_JOB_ID}.log"
apptainer exec "$SIF" ollama serve > "$LOG" 2>&1 &
OLLAMA_PID=$!

cleanup() { kill "$OLLAMA_PID" 2>/dev/null || true; }
trap cleanup EXIT

# Wait until Ollama is ready
for i in {1..120}; do
  if curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "[FATAL] Ollama server did not start." >&2
  tail -n 200 "$LOG" || true
  exit 1
fi

# Pull model only if missing (stored in $OLLAMA_MODELS on RDS)
MODEL="llama2:7b"
if ! apptainer exec "$SIF" ollama list | awk '{print $1}' | grep -qx "$MODEL"; then
  echo "[INFO] Pulling model: $MODEL"
  apptainer exec "$SIF" ollama pull "$MODEL"
else
  echo "[INFO] Model already present: $MODEL"
fi

# ----------------------------
# Runtime knobs for your Python script
# ----------------------------
export OLLAMA_MODEL="$MODEL"
export OLLAMA_THREADS="${SLURM_CPUS_PER_TASK}"
export OLLAMA_WORKERS=1
export BATCH_SIZE=20
export OLLAMA_TIMEOUT=1800
export OLLAMA_RETRIES=2

export MAX_PAIRS=50000
export OLLAMA_NUM_PREDICT=32
export OLLAMA_NUM_CTX=2048

# ----------------------------
# Run
# ----------------------------
cd ~/projects/Mapping_Behav_RL
python Mapping_landscape_ABM/2.1_semantic_ratings.py