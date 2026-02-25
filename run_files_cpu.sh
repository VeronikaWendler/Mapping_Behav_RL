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

# ---- Put Apptainer build/cache somewhere BIG and persistent (NOT HOME, NOT /tmp)
export APPTAINER_TMPDIR="/rds/projects/z/zhanglp-vwendler-core/apptainer_tmp"
export APPTAINER_CACHEDIR="/rds/projects/z/zhanglp-vwendler-core/apptainer_cache"
mkdir -p "$APPTAINER_TMPDIR" "$APPTAINER_CACHEDIR"

# ---- Python hygiene
export MPLCONFIGDIR="${SLURM_TMPDIR:-/tmp}/mplcache"
export PYTHONUNBUFFERED=1
export TOKENIZERS_PARALLELISM=false
export PYTHONNOUSERSITE=1

source ~/apps/miniforge3/etc/profile.d/conda.sh
conda activate mapping_abm

# ---- Container location on RDS
CONTAINERS_DIR="/rds/projects/z/zhanglp-vwendler-core/containers"
SIF="${CONTAINERS_DIR}/ollama_latest.sif"
mkdir -p "$CONTAINERS_DIR"

if [ ! -f "$SIF" ]; then
  echo "[INFO] Pulling Ollama container to: $SIF"
  apptainer pull "$SIF" docker://ollama/ollama
else
  echo "[INFO] Using existing container: $SIF"
fi

# ---- IMPORTANT: run Ollama models in SLURM_TMPDIR (always writable on compute nodes)
export OLLAMA_MODELS="${SLURM_TMPDIR}/ollama_models"
mkdir -p "$OLLAMA_MODELS"
echo "[INFO] OLLAMA_MODELS=$OLLAMA_MODELS"
df -h "$SLURM_TMPDIR" || true

# ---- Bind the needed host paths into the container (read access for your code/data paths)
BIND="/rds:/rds,/tmp:/tmp"

# ---- Start Ollama server
LOG="ollama_server.${SLURM_JOB_ID}.log"
apptainer exec --bind "$BIND" "$SIF" ollama serve > "$LOG" 2>&1 &
OLLAMA_PID=$!

cleanup() { kill "$OLLAMA_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ---- Wait for server
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

# ---- Pull model (this will download into $SLURM_TMPDIR/ollama_models)
MODEL="llama2:7b"
echo "[INFO] Pulling model if needed: $MODEL"
apptainer exec --bind "$BIND" "$SIF" ollama pull "$MODEL" || true
apptainer exec --bind "$BIND" "$SIF" ollama list || true

# ---- Runtime knobs for your Python script
export OLLAMA_MODEL="$MODEL"
export OLLAMA_THREADS="${SLURM_CPUS_PER_TASK}"
export OLLAMA_WORKERS=1
export BATCH_SIZE=20
export OLLAMA_TIMEOUT=1800
export OLLAMA_RETRIES=2
export MAX_PAIRS=50000
export OLLAMA_NUM_PREDICT=32
export OLLAMA_NUM_CTX=2048

# ---- Run from your HOME repo, but output paths should be RDS in the Python script
cd ~/projects/Mapping_Behav_RL
python Mapping_landscape_ABM/2.1_semantic_ratings.py