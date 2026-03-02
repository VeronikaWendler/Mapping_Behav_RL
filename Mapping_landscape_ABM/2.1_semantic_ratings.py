import os
import re
import time
import json
import csv
import random
import signal
import requests
import concurrent.futures
import pandas as pd

# ----------------------------
# Ollama local
# ----------------------------
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434/api/generate")
MODEL = os.environ.get("OLLAMA_MODEL", "llama3.3:70b")  # match what you pull in the .sh

# ----------------------------
# Output parsing: accepts Answer=[n], Answer=n, Answer: n
# ----------------------------
ANSWER_RE = re.compile(r"^\s*Answer\s*[:=]\s*\[?(\d{1,3})\]?\s*$", re.MULTILINE)

def extract_rating_or_die(text: str) -> int:
    if text is None:
        raise RuntimeError("Model returned None")
    s = str(text).strip()
    if not s:
        raise RuntimeError("Empty model response")

    matches = list(ANSWER_RE.finditer(s))
    if not matches:
        raise RuntimeError(f"Missing Answer line. Got (first 300 chars): {s[:300]}")

    val = int(matches[-1].group(1))
    if not (0 <= val <= 100):
        raise RuntimeError(f"Rating out of range (0-100): {val}")

    return val

def extract_one_sentence_reasoning(text: str) -> str:
    """
    Extract a single-sentence reasoning line from the model output.
    - Takes the first non-empty line that is NOT the Answer line.
    - Truncates to one sentence (up to first '.') and max 240 chars.
    """
    if not text:
        return ""
    s = str(text).strip()
    lines = [ln.strip() for ln in s.splitlines() if ln.strip()]
    for ln in lines:
        if ANSWER_RE.search(ln):
            continue
        if "." in ln:
            ln = ln.split(".", 1)[0].strip() + "."
        return ln[:240]
    return ""

def ensure_ollama_up_or_die():
    try:
        r = requests.get("http://127.0.0.1:11434/api/tags", timeout=10)
        if r.status_code != 200:
            raise RuntimeError(f"Ollama not ready: {r.status_code} {r.text[:200]}")
    except Exception as e:
        raise SystemExit(f"[FATAL] Local Ollama not reachable at 127.0.0.1:11434: {e}")

def atomic_write_csv(df: pd.DataFrame, path: str):
    tmp = path + ".tmp"
    df.to_csv(tmp, index=False, quoting=csv.QUOTE_ALL)
    os.replace(tmp, path)

def run_one(prompt: str, timeout: int, max_retries: int) -> str:
    """
    One request with retry/backoff.
    IMPORTANT: We do NOT set temperature/num_predict/num_ctx etc.
    We use server/model defaults (like the researchers' hosted API code).
    """
    payload = {
        "model": MODEL,
        "system": SYSTEM_PROMPT,
        "prompt": prompt,
        "stream": False,
    }

    for attempt in range(max_retries):
        try:
            r = requests.post(OLLAMA_URL, json=payload, timeout=timeout)
            if r.status_code != 200:
                raise RuntimeError(f"Ollama HTTP {r.status_code}: {r.text[:300]}")
            j = r.json()
            return j.get("response", "")
        except requests.exceptions.Timeout:
            time.sleep(min(10, (2 ** attempt) + random.random()))
        except Exception:
            if attempt == max_retries - 1:
                raise
            time.sleep(min(10, (2 ** attempt) + random.random()))

    return "ERROR max_retries_exceeded"

# ----------------------------
# Paths
# ----------------------------
in_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs.csv"
out_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_ratings.csv"
audit_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_ratings_audit.jsonl"

# ----------------------------
# Prompt content (close to researchers; one-sentence reasoning)
# ----------------------------
SYSTEM_PROMPT = (
    "You are an expert in the academic literature on behavioral agent-based modeling (ABM), "
    "who accurately discerns differences in specific research topics."
)

TASK_DESCRIPTION = """Your primary task is to compare the following two articles (Article 1 and Article 2) based *only* on their provided titles and abstracts.

Both articles use or discuss agent-based modeling (ABM), but IMPORTANT: sharing ABM as a method does NOT imply similar research topics.

Your goal is to determine how similar their *specific research topics* are within behavioral ABM.
Do they investigate the same domain problem, behavioral mechanism, or research question?
"""

FORMAT_INSTRUCTIONS = """
First, provide exactly ONE sentence of reasoning (no bullet points, no headings).
Second, output the numerical rating on a new line.

Rate the similarity of the specific research topics on a continuous scale from 0 to 100:
* 0: Completely different specific research topics (only both using ABM is NOT similarity).
* 50: The articles share significant common ground but address distinct specific topics.
* 100: The articles address the same specific research topic.

Strictly format the rating line *exactly* like this, with no extra text before or after:
Answer=[rating]
""".strip()

def clean_text(x) -> str:
    if x is None:
        return ""
    if isinstance(x, float) and pd.isna(x):
        return ""
    s = str(x).strip()
    if s.lower() == "nan":
        return ""
    return s

def build_prompt(train: pd.DataFrame, idx: int) -> str:
    t1 = clean_text(train.at[idx, "text_i"])
    t2 = clean_text(train.at[idx, "text_j"])
    pair = f"-- Article 1 --\n{t1}\n\n-- Article 2 --\n{t2}"
    return f"{TASK_DESCRIPTION}\n\nHere are the articles to evaluate:\n\n{pair}\n\n{FORMAT_INSTRUCTIONS}\n"

# ----------------------------
# Graceful shutdown: save progress on SIGTERM/SIGINT
# ----------------------------
STOP_REQUESTED = False
def _handle_stop(signum, frame):
    global STOP_REQUESTED
    STOP_REQUESTED = True
    print(f"\n[WARN] Received signal {signum}. Will stop after current batch and save progress.", flush=True)

signal.signal(signal.SIGTERM, _handle_stop)
signal.signal(signal.SIGINT, _handle_stop)

def main():
    ensure_ollama_up_or_die()
    print(f"[OK] Using local Ollama model: {MODEL}", flush=True)

    base = pd.read_csv(in_path)
    print(f"Total rows in train_pairs.csv: {len(base)}", flush=True)

    # SAFETY CAP
    max_pairs = int(os.environ.get("MAX_PAIRS", "10000"))
    if len(base) > max_pairs:
        print(f"[WARN] Capping to MAX_PAIRS={max_pairs} (from {len(base)})", flush=True)
        base = base.iloc[:max_pairs].copy()

    # Resume if exists
    if os.path.exists(out_path):
        train = pd.read_csv(out_path, engine="python", on_bad_lines="error")
        for col in base.columns:
            if col not in train.columns:
                train[col] = base[col]
        if "out" not in train.columns:
            train["out"] = ""
        if "out_raw" not in train.columns:
            train["out_raw"] = ""
    else:
        train = base.copy()
        train["out"] = ""
        train["out_raw"] = ""

    # Done iff Answer line is present (strict)
    def is_done_out(x: str) -> bool:
        if not isinstance(x, str):
            return False
        return bool(ANSWER_RE.search(x))

    done_mask = train["out"].fillna("").astype(str).apply(is_done_out)
    start_idx = int(train.index[~done_mask].min()) if (~done_mask).any() else len(train)

    # Runtime knobs
    workers = int(os.environ.get("OLLAMA_WORKERS", "1"))
    batch_size = int(os.environ.get("BATCH_SIZE", "20"))
    timeout = int(os.environ.get("OLLAMA_TIMEOUT", "600"))
    max_retries = int(os.environ.get("OLLAMA_RETRIES", "2"))

    print(f"Already completed: {int(done_mask.sum())}", flush=True)
    print(f"Starting at index: {start_idx}", flush=True)
    print(f"workers={workers} batch_size={batch_size} MAX_PAIRS={max_pairs}", flush=True)
    print(f"timeout={timeout} retries={max_retries}", flush=True)

    os.makedirs(os.path.dirname(audit_path), exist_ok=True)
    audit_f = open(audit_path, "a", encoding="utf-8")

    # Smoke test
    smoke_prompt = (
        f"{TASK_DESCRIPTION}\n\nHere are the articles to evaluate:\n\n"
        f"-- Article 1 --\nTitle: A\nAbstract: A\n\n-- Article 2 --\nTitle: B\nAbstract: B\n\n"
        f"{FORMAT_INSTRUCTIONS}\n"
    )
    smoke_raw = run_one(smoke_prompt, timeout=timeout, max_retries=max_retries)
    print("[SMOKE] raw:", repr(smoke_raw[:220]), flush=True)
    try:
        _ = extract_rating_or_die(smoke_raw)
        print("[SMOKE] parse OK", flush=True)
    except Exception:
        print("[FATAL] Smoke test failed; output not parseable.", flush=True)
        print("Raw was:\n", smoke_raw, flush=True)
        raise SystemExit(2)

    try:
        for begin in range(start_idx, len(train), batch_size):
            if STOP_REQUESTED:
                print("[WARN] Stop requested; saving and exiting now.", flush=True)
                break

            end = min(begin + batch_size, len(train))
            idxs = [i for i in range(begin, end) if not is_done_out(str(train.at[i, "out"]))]

            if not idxs:
                continue

            # Skip rows with missing text
            filtered = []
            for i in idxs:
                t1 = clean_text(train.at[i, "text_i"])
                t2 = clean_text(train.at[i, "text_j"])
                if len(t1) < 30 or len(t2) < 30:
                    train.at[i, "out"] = "ERROR: missing_text"
                    train.at[i, "out_raw"] = ""
                else:
                    filtered.append(i)
            idxs = filtered

            if not idxs:
                atomic_write_csv(train, out_path)
                continue

            prompts = [build_prompt(train, i) for i in idxs]

            def call(p: str) -> str:
                return run_one(p, timeout=timeout, max_retries=max_retries)

            t0 = time.time()
            if workers == 1:
                results = [call(p) for p in prompts]
            else:
                with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
                    results = list(ex.map(call, prompts))

            print(f"\n[BATCH] {begin}..{end-1} (calling {len(idxs)} rows)", flush=True)

            ok = 0
            err = 0

            for k, (i, raw) in enumerate(zip(idxs, results), start=1):
                if k <= 3:
                    sample = (raw or "").strip().replace("\n", " | ")
                    print(f"[SAMPLE row={i}] {sample[:260]}", flush=True)

                try:
                    rating = extract_rating_or_die(raw)
                    reason = extract_one_sentence_reasoning(raw)
                    train.at[i, "out"] = f"Answer=[{rating}]"
                    train.at[i, "out_raw"] = reason
                    ok += 1
                except Exception as e:
                    train.at[i, "out"] = f"ERROR: {type(e).__name__}: {str(e)[:120]}"
                    train.at[i, "out_raw"] = extract_one_sentence_reasoning(raw)
                    err += 1

                audit_f.write(json.dumps({
                    "row_idx": int(i),
                    "i": int(train.at[i, "i"]) if "i" in train.columns and pd.notna(train.at[i, "i"]) else None,
                    "j": int(train.at[i, "j"]) if "j" in train.columns and pd.notna(train.at[i, "j"]) else None,
                    "out": str(train.at[i, "out"])[:200],
                    "reason": str(train.at[i, "out_raw"])[:240],
                    "raw": (raw or "")[:500],
                }) + "\n")

            audit_f.flush()
            atomic_write_csv(train, out_path)

            dt = time.time() - t0
            rate = (len(idxs) / dt) if dt > 0 else 0
            print(f"[DONE] rows {begin}..{end-1} | ok={ok} err={err} | {dt:.1f}s | {rate:.2f} rows/s", flush=True)

    finally:
        audit_f.close()
        atomic_write_csv(train, out_path)
        print(f"[OK] Saved progress to: {out_path}", flush=True)

if __name__ == "__main__":
    main()
























# import os
# import re
# import time
# import json
# import csv
# import random
# import requests
# import concurrent.futures
# import pandas as pd

# # ----------------------------
# # Ollama local
# # ----------------------------
# OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
# MODEL = os.environ.get("OLLAMA_MODEL", "llama2:7b")

# # ----------------------------
# # Parse: accept Answer=[n], Answer=n, Answer: n
# # (handles your observed output: "Answer: 85")
# # ----------------------------
# ANSWER_RE = re.compile(r"^\s*Answer\s*[:=]\s*\[?(\d{1,3})\]?\s*$", re.MULTILINE)

# def extract_rating_or_die(text: str) -> int:
#     if text is None:
#         raise RuntimeError("Model returned None")
#     s = str(text).strip()
#     if not s:
#         raise RuntimeError("Empty model response")

#     matches = list(ANSWER_RE.finditer(s))
#     if not matches:
#         raise RuntimeError(f"Missing Answer line. Got (first 300 chars): {s[:300]}")

#     val = int(matches[-1].group(1))
#     if not (0 <= val <= 100):
#         raise RuntimeError(f"Rating out of range (0-100): {val}")

#     return val

# def ensure_ollama_up_or_die():
#     try:
#         r = requests.get("http://127.0.0.1:11434/api/tags", timeout=10)
#         if r.status_code != 200:
#             raise RuntimeError(f"Ollama not ready: {r.status_code} {r.text[:200]}")
#     except Exception as e:
#         raise SystemExit(f"[FATAL] Local Ollama not reachable at 127.0.0.1:11434: {e}")

# def atomic_write_csv(df: pd.DataFrame, path: str):
#     tmp = path + ".tmp"
#     df.to_csv(tmp, index=False, quoting=csv.QUOTE_ALL)
#     os.replace(tmp, path)

# def run_one(prompt: str, num_threads: int, timeout: int, max_retries: int) -> str:
#     payload = {
#         "model": MODEL,
#         "system": SYSTEM_PROMPT,
#         "prompt": prompt,
#         "stream": False,
#         "options": {
#             "temperature": 0,
#             # Answer-only => keep generation short
#             "num_predict": int(os.environ.get("OLLAMA_NUM_PREDICT", "32")),
#             "num_thread": num_threads,
#             # reduce ctx if you want speed; 2048 is often enough for abstracts
#             "num_ctx": int(os.environ.get("OLLAMA_NUM_CTX", "2048")),
#         }
#     }

#     for attempt in range(max_retries):
#         try:
#             r = requests.post(OLLAMA_URL, json=payload, timeout=timeout)
#             if r.status_code != 200:
#                 raise RuntimeError(f"Ollama HTTP {r.status_code}: {r.text[:300]}")
#             j = r.json()
#             return j.get("response", "")
#         except requests.exceptions.Timeout:
#             time.sleep(min(5, 2 ** attempt + random.random()))
#         except Exception:
#             if attempt == max_retries - 1:
#                 raise
#             time.sleep(min(5, 2 ** attempt + random.random()))

#     raise RuntimeError("max_retries_exceeded")

# # ----------------------------
# # Paths
# # ----------------------------
# in_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs.csv"
# out_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_ratings.csv"
# audit_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_ratings_audit.jsonl"

# # ----------------------------
# # Prompt content (Answer-only)
# # ----------------------------
# SYSTEM_PROMPT = (
#     "You are an expert in the academic literature on behavioral agent-based modeling (ABM), "
#     "who accurately discerns differences in specific research topics."
# )

# TASK_DESCRIPTION = """Compare Article 1 and Article 2 based only on their titles and abstracts.
# Both are in behavioral agent-based modeling (ABM).

# Rate how similar their specific research topics are within ABM on a scale 0-100:
# 0 = completely different topics
# 50 = related but distinct topics
# 100 = same topic
# """

# FORMAT_INSTRUCTIONS = """
# Return ONLY one line exactly in this format (no other text):
# Answer=[rating]
# where rating is an integer from 0 to 100.
# """.strip()

# def build_prompt(train: pd.DataFrame, idx: int) -> str:
#     pair = (
#         "-- Article 1 --\n" + str(train.at[idx, "text_i"]) +
#         "\n\n-- Article 2 --\n" + str(train.at[idx, "text_j"])
#     )
#     return f"{TASK_DESCRIPTION}\n{pair}\n\n{FORMAT_INSTRUCTIONS}\n"

# def main():
#     ensure_ollama_up_or_die()
#     print(f"[OK] Using local Ollama model: {MODEL}", flush=True)

#     base = pd.read_csv(in_path)
#     print(f"Total rows in train_pairs.csv: {len(base)}", flush=True)

#     # SAFETY CAP (prevents accidental millions)
#     max_pairs = int(os.environ.get("MAX_PAIRS", "20000"))    #should be 50 000 but for speed 20 000
#     if len(base) > max_pairs:
#         print(f"[WARN] Capping to MAX_PAIRS={max_pairs} (from {len(base)})", flush=True)
#         base = base.iloc[:max_pairs].copy()

#     # Resume if exists
#     if os.path.exists(out_path):
#         train = pd.read_csv(out_path, engine="python", on_bad_lines="error")
#         # Ensure base columns exist
#         for col in base.columns:
#             if col not in train.columns:
#                 train[col] = base[col]
#         if "out" not in train.columns:
#             train["out"] = ""
#         if "out_raw" not in train.columns:
#             train["out_raw"] = ""
#     else:
#         train = base.copy()
#         train["out"] = ""
#         train["out_raw"] = ""

#     def is_done_out(x: str) -> bool:
#         # done iff we have a standardized Answer=[n] or at least an Answer=... line
#         if not isinstance(x, str):
#             return False
#         return bool(ANSWER_RE.search(x)) or ("Answer=" in x)

#     done_mask = train["out"].fillna("").astype(str).apply(is_done_out)
#     start_idx = int(train.index[~done_mask].min()) if (~done_mask).any() else len(train)

#     # Performance knobs
#     workers = int(os.environ.get("OLLAMA_WORKERS", "1"))
#     batch_size = int(os.environ.get("BATCH_SIZE", "20"))
#     num_threads = int(os.environ.get("OLLAMA_THREADS", os.environ.get("SLURM_CPUS_PER_TASK", "8")))
#     timeout = int(os.environ.get("OLLAMA_TIMEOUT", "1800"))
#     max_retries = int(os.environ.get("OLLAMA_RETRIES", "2"))

#     print(f"Already completed: {int(done_mask.sum())}", flush=True)
#     print(f"Starting at index: {start_idx}", flush=True)
#     print(f"workers={workers} batch_size={batch_size} num_threads={num_threads} MAX_PAIRS={max_pairs}", flush=True)

#     os.makedirs(os.path.dirname(audit_path), exist_ok=True)
#     audit_f = open(audit_path, "a", encoding="utf-8")

#     try:
#         for begin in range(start_idx, len(train), batch_size):
#             end = min(begin + batch_size, len(train))
#             idxs = [i for i in range(begin, end) if not is_done_out(str(train.at[i, "out"]))]

#             if not idxs:
#                 continue

#             t0 = time.time()
#             prompts = [build_prompt(train, i) for i in idxs]

#             def call(p):
#                 return run_one(p, num_threads=num_threads, timeout=timeout, max_retries=max_retries)

#             if workers == 1:
#                 results = [call(p) for p in prompts]
#             else:
#                 with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
#                     results = list(ex.map(call, prompts))

#             for k, (i, raw) in enumerate(zip(idxs, results), start=1):
#                 # ✅ NEW: robust per-row error handling
#                 try:
#                     rating = extract_rating_or_die(raw)
#                     out_line = f"Answer=[{rating}]"
#                     train.at[i, "out"] = out_line
#                     train.at[i, "out_raw"] = raw[:500]
#                 except Exception as e:
#                     train.at[i, "out"] = f"ERROR: {type(e).__name__}: {str(e)[:120]}"
#                     train.at[i, "out_raw"] = (raw or "")[:500]

#                 audit_f.write(json.dumps({
#                     "row_idx": int(i),
#                     "i": int(train.at[i, "i"]) if "i" in train.columns and pd.notna(train.at[i, "i"]) else None,
#                     "j": int(train.at[i, "j"]) if "j" in train.columns and pd.notna(train.at[i, "j"]) else None,
#                     "out": str(train.at[i, "out"])[:200],
#                     "raw": (raw or "")[:500],
#                 }) + "\n")

#                 if (k % 20) == 0:
#                     print(f"progress: row {i} ({i+1}/{len(train)})", flush=True)

#             audit_f.flush()
#             atomic_write_csv(train, out_path)

#             dt = time.time() - t0
#             print(f"Batch {begin//batch_size + 1}: rows {begin}..{end-1} done={len(idxs)} in {dt:.1f}s", flush=True)

#     finally:
#         audit_f.close()

# if __name__ == "__main__":
#     main()













# import os
# import time
# import random
# import requests
# import concurrent.futures
# import pandas as pd
# from functools import partial
# import sys
# import json
# import warnings

# # ----------------------------
# # read hidden api
# with open("Mapping_landscape_ABM/Data/semantic_training/api.txt", "r") as f:
#     url = f.readline().strip()
#     auth = f.readline().strip()

# headers = {"Authorization": auth, "Content-Type": "application/json"}

# MODEL = "meta-llama/Llama-3.3-70B-Instruct" 

# def run(system, user, timeout=120, max_retries=6):
#     """One request with retry/backoff. Returns model text or an ERROR string."""
#     payload = {
#         "model": MODEL,
#         "messages": [
#             {"role": "system", "content": system},
#             {"role": "user", "content": user},
#         ],
#     }

#     for attempt in range(max_retries):
#         try:
#             r = requests.post(url, headers=headers, json=payload, timeout=timeout)

#             # Success
#             if r.status_code == 200:
#                 j = r.json()
#                 return j["choices"][0]["message"]["content"]

#             # Common transient failures (rate limits / overload)
#             if r.status_code in (429, 500, 502, 503, 504):
#                 sleep_s = min(60, (2 ** attempt) + random.random())
#                 time.sleep(sleep_s)
#                 continue

#             if r.status_code == 400:
#                 # try to parse OpenAI-style error payload
#                 try:
#                     j = r.json()
#                     code = j.get("error", {}).get("code")
#                     msg = j.get("error", {}).get("message", "")
#                 except Exception:
#                     code, msg = None, ""

#                 if code == "model_not_found" or "does not exist" in r.text.lower():
#                     raise SystemExit(
#                         f"[FATAL] Model '{MODEL}' not found (server says model_not_found). "
#                         f"Fix MODEL or endpoint.\nBody={r.text[:500]}"
#                     )

#             # Other errors: keep the body for debugging
#             return f"ERROR status={r.status_code} body={r.text[:300]}"

#         except requests.exceptions.Timeout:
#             sleep_s = min(60, (2 ** attempt) + random.random())
#             time.sleep(sleep_s)
#             continue
#         except Exception as e:
#             return f"ERROR exception={type(e).__name__} msg={str(e)[:200]}"

#     return "ERROR max_retries_exceeded"

# def run_parallel_map(system_prompt, users, workers=5):
#     func = partial(run, system_prompt)
#     with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
#         return list(ex.map(func, users))

# # check

# def verify_model_or_die(timeout=30):
#     payload = {
#         "model": MODEL,
#         "messages": [{"role": "user", "content": "Reply with: OK"}],
#         "max_tokens": 5,
#         "temperature": 0,
#     }
#     try:
#         r = requests.post(url, headers=headers, json=payload, timeout=timeout)
#     except Exception as e:
#         raise SystemExit(f"[FATAL] Cannot reach API endpoint: {type(e).__name__}: {e}")

#     if r.status_code == 200:
#         print(f"[OK] Model '{MODEL}' is available.")
#         return

#     # Try to parse structured error
#     err_text = r.text[:500]
#     try:
#         j = r.json()
#         code = j.get("error", {}).get("code")
#         msg = j.get("error", {}).get("message", "")
#     except Exception:
#         code, msg = None, ""

#     if code == "model_not_found" or "does not exist" in err_text.lower():
#         raise SystemExit(
#             f"[FATAL] Model '{MODEL}' not found/available on this endpoint.\n"
#             f"Status={r.status_code}\n"
#             f"Message={msg or err_text}"
#         )

#     raise SystemExit(
#         f"[FATAL] API request failed during model check.\n"
#         f"Status={r.status_code}\n"
#         f"Body={err_text}"
#     )

# verify_model_or_die()


# # ----------------------------
# # Paths
# # ----------------------------
# in_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs.csv"
# out_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs_ratings.csv"

# # Load existing progress if present
# if os.path.exists(out_path):
#     train = pd.read_csv(out_path)
#     if "out" not in train.columns:
#         train["out"] = ""
# else:
#     train = pd.read_csv(in_path)
#     train["out"] = ""

# pairs = ["-- Article 1 --\n" + i + "\n\n-- Article 2 --\n" + j for i, j in zip(train["text_i"].values, train["text_j"].values)]

# system_prompt = "You are an expert in the academic literature on behavioral agent-based modeling (ABM), who accurately discerns differences in specific research topics."
# task_description = """Your primary task is to compare the following two articles (Article 1 and Article 2) based *only* on their provided titles and abstracts. Both articles operate within the general field of behavioral agent-based modeling (ABM).\n\nYour goal is to determine how similar their *specific research topics* are within the ABM context. Do they investigate the same sub-problem, mechanism, or research question?"""
# format_instructions = """
# First, provide your reasoning:
# **Reasoning:**
# [Provide a brief explanation here comparing the specific research topics, methodologies, or questions apparent in the titles/abstracts. Highlight similarities and differences relevant to the ABM field.]

# Second, immediately following your reasoning, provide the numerical rating on a new line using the specified format.
# Rate the similarity of the specific research topics on a scale from 0 to 100:
# * **0:** Completely different specific research topics within ABM.
# * **50:** The articles share significant common ground but ultimately address distinct specific research topics within ABM.
# * **100:** The articles address the same specific research topic within ABM.

# Strictly format the rating line *exactly* like this, with no extra text before or after:
# Answer=[rating]"""

# prompt_prefix = task_description + "\n\n"
# final_user_prompts = [
#     prompt_prefix + f"Here are the articles to evaluate:\n\n{pair}\n\n" + format_instructions
#     for pair in pairs
# ]

# # ----------------------------
# # Resume logic: only Answer= counts as done
# # ----------------------------
# out_series = train["out"].fillna("").astype(str)
# done_mask = out_series.str.contains("Answer=")

# # Start at first not-done index (not "count of non-empty")
# not_done_idx = train.index[~done_mask]
# start_idx = int(not_done_idx.min()) if len(not_done_idx) else len(train)

# batch_size = 100
# num_prompts = len(final_user_prompts)

# print(f"Total prompts: {num_prompts}")
# print(f"Already completed (Answer=): {done_mask.sum()}")
# print(f"Starting at index: {start_idx}")

# # ----------------------------
# # Main loop
# # ----------------------------
# for i in range(start_idx, num_prompts, batch_size):
#     begin = i
#     end = min(begin + batch_size, num_prompts)
#     current_prompts = final_user_prompts[begin:end]

#     t0 = time.time()
#     batch_results = run_parallel_map(system_prompt, current_prompts, workers=5)

#     train.iloc[begin:end, train.columns.get_loc("out")] = batch_results
#     train.to_csv(out_path, index=False)

#     dt = time.time() - t0
#     print(f"Batch {begin//batch_size + 1}: {begin}..{end-1} in {dt:.2f}s")









# import os
# import time
# import random
# import re
# import requests
# import concurrent.futures
# import pandas as pd
# from functools import partial


# PILOT_N = 500      
# BATCH_SIZE = 10
# WORKERS = 2
# TIMEOUT = 120
# MAX_RETRIES = 6

# MODEL = "meta-llama/Llama-3.3-70B-Instruct"
# MAX_TOKENS = 10
# TEMPERATURE = 0.0

# ANSWER_RE = re.compile(r"Answer\s*=\s*(\d{1,3})")


# API_PATH = "Mapping_landscape_ABM/Data/semantic_training/api.txt"
# with open(API_PATH, "r") as f:
#     url = f.readline().strip()
#     auth = f.readline().strip()

# headers = {"Authorization": auth, "Content-Type": "application/json"}

# # ----------------------------

# def run(system, user, timeout=TIMEOUT, max_retries=MAX_RETRIES):
#     payload = {
#         "model": MODEL,
#         "messages": [
#             {"role": "system", "content": system},
#             {"role": "user", "content": user},
#         ],
#         "max_tokens": MAX_TOKENS,
#         "temperature": TEMPERATURE,
#     }

#     for attempt in range(max_retries):
#         try:
#             r = requests.post(url, headers=headers, json=payload, timeout=timeout)

#             if r.status_code == 200:
#                 j = r.json()
#                 txt = j["choices"][0]["message"]["content"]
#                 return txt.strip()

#             # transient
#             if r.status_code in (408, 429, 500, 502, 503, 504):
#                 time.sleep(min(60, (2 ** attempt) + random.random()))
#                 continue

#             # non-transient: auth/billing/access/model not found
#             return f"ERROR status={r.status_code} body={r.text[:300]}"

#         except requests.exceptions.Timeout:
#             time.sleep(min(60, (2 ** attempt) + random.random()))
#             continue
#         except Exception as e:
#             return f"ERROR exception={type(e).__name__} msg={str(e)[:200]}"

#     return "ERROR max_retries_exceeded"


# def run_parallel(system_prompt, users):
#     func = partial(run, system_prompt)
#     results = [None] * len(users)
#     with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as ex:
#         futs = {ex.submit(func, u): i for i, u in enumerate(users)}
#         for fut in concurrent.futures.as_completed(futs):
#             i = futs[fut]
#             try:
#                 results[i] = fut.result()
#             except Exception as e:
#                 results[i] = f"ERROR exception={repr(e)}"
#     return results


# # ----------------------------
# # Paths
# in_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs.csv"
# out_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs_ratings.csv"

# # load
# if os.path.exists(out_path):
#     train = pd.read_csv(out_path)
#     if "out" not in train.columns:
#         train["out"] = ""
# else:
#     train = pd.read_csv(in_path)
#     train["out"] = ""

# out_series = train["out"].fillna("").astype(str)
# done_mask = out_series.str.contains(r"Answer\s*=", regex=True)

# not_done_idx = train.index[~done_mask]
# start_idx = int(not_done_idx.min()) if len(not_done_idx) else len(train)

# end_total = min(len(train), start_idx + PILOT_N)

# print(f"Total rows in train_pairs: {len(train)}")
# print(f"Already completed (Answer=): {int(done_mask.sum())}")
# print(f"Pilot will run rows: {start_idx}..{end_total-1} (N={end_total-start_idx})")


# system_prompt = (
#     "You are an expert in the academic literature on agent-based modeling (ABM). "
#     "Return ONLY a single line exactly in the format Answer=NN where NN is an integer 0-100."
# )

# task_description = (
#     "Compare Article 1 and Article 2 based only on title and abstract. "
#     "Rate similarity of their specific ABM research topic from 0 (completely different) "
#     "to 100 (same topic). Return ONLY: Answer=NN"
# )

# sub = train.iloc[start_idx:end_total]

# pairs = [
#     "-- Article 1 --\n" + str(i) + "\n\n-- Article 2 --\n" + str(j)
#     for i, j in zip(sub["text_i"].values, sub["text_j"].values)
# ]
# prompts = [f"{task_description}\n\n{pair}\n\nReturn ONLY: Answer=NN" for pair in pairs]


# print("\nSMOKE TEST...")
# smoke = run(system_prompt, "Return ONLY: Answer=7")
# print("SMOKE OUT:", smoke)
# if not ANSWER_RE.search(smoke or ""):
#     raise SystemExit("Smoke test failed (no Answer=NN). Not running pilot.")



# for begin in range(start_idx, end_total, BATCH_SIZE):
#     end = min(begin + BATCH_SIZE, end_total)
#     current_prompts = prompts[begin - start_idx : end - start_idx]

#     t0 = time.time()
#     batch_out = run_parallel(system_prompt, current_prompts)

#     cleaned = []
#     for x in batch_out:
#         m = ANSWER_RE.search(x or "")
#         if m:
#             nn = int(m.group(1))
#             nn = max(0, min(100, nn))
#             cleaned.append(f"Answer={nn}")
#         else:
#             cleaned.append(x if x else "ERROR empty")

#     train.iloc[begin:end, train.columns.get_loc("out")] = cleaned
#     train.to_csv(out_path, index=False)

#     n_ans = sum(bool(ANSWER_RE.search(x or "")) for x in cleaned)
#     n_err = sum((x or "").startswith("ERROR") for x in cleaned)
#     print(f"Batch {begin//BATCH_SIZE + 1}: {begin}..{end-1} in {time.time()-t0:.1f}s | OK={n_ans}/{len(cleaned)} | ERR={n_err}")
