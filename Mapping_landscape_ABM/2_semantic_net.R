require(tidyverse)
require(reticulate)
Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required=TRUE)
print(py_config())

require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

# data = read_csv("Mapping_landscape_ABM/Data/data_cleaned_filtered_4_1000.csv") |> mutate(text = paste0("Title: ", Title, ".\nAbstract: ", Abstract_cleaned))

# # GENERATE TRAINING EXAMPLES -----
# #reticulate::py_install("sentence-transformers")
# #use_python("/path/to/python", required = TRUE)

# sbert = import("sentence_transformers")
# model = sbert$SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
# embed = model$encode(data$text, show_progress_bar = TRUE)
# embed_cos = arma_cosine(embed)
# embed_cos[embed_cos > 1] = 1 ; embed_cos[embed_cos < -1] = -1
# embed_acos = 1-acos(embed_cos)/pi
# rownames(embed_acos) = colnames(embed_acos) = data$id

# clust = hclust(as.dist(1-embed_acos[as.character(data$id),as.character(data$id)])) |> cutree(k = 50)
# names(clust) = data$id

# pairs = crossing(i = data$id,
#                  j = data$id) |> 
#   filter(i < j) |> 
#   mutate(cl_i = clust[as.character(i)],
#          cl_j = clust[as.character(j)],
#          cos = embed_acos[cbind(as.character(i), as.character(j))])

# set.seed(100)
# train_pairs = lapply(1:50, function(x){
  
#   within = pairs |> filter(cl_i == x, cl_j == x) |> mutate(type = "within")
#   between = pairs |> filter((cl_i == x & cl_j != x) | cl_i != x & cl_j == x) |> mutate(type = "between")
  
#   sel_within = sample(nrow(within), min(1000, nrow(within)), prob = within$cos ** 10)
#   sel_between = sample(nrow(between), min(1000, nrow(between)), prob = between$cos ** 10)
  
#   within = within |> slice(sel_within)
#   between = between |> slice(sel_between)
  
#   tibble(within) |> bind_rows(between) |> mutate(cl = x)
#   }) |> bind_rows() |> slice(sample(n(), 50000))

# texts = data |> pull(text, id)
# train_pairs = train_pairs |> 
#   mutate(text_i = texts[as.character(i)],
#          text_j = texts[as.character(j)])

# out_file <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs.csv"
# dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
# write_csv(train_pairs, out_file)



# PROCESS RATINGS -----------------------------------------------------------------------------------------------

# train_pairs_ratings = read_csv("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_ratings.csv") |> 
#   mutate(
#     rating = out |> str_extract("Answer=[:digit:]+") |> str_remove("Answer=") |> as.numeric(),
#     rating_scaled = rating / 100
#   ) |> 
#   filter(!is.na(rating_scaled)) |>          # drop ERROR rows / blanks
#   select(-1)                                # keep if your CSV has an X1 index column; otherwise remove

# write_csv(train_pairs_ratings, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_rating_clean.csv")

###------

# in_file  <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_ratings.csv"
# out_file <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_rating_clean.csv"
# train_pairs_ratings <- read_csv(in_file, show_col_types = FALSE)

# index_like <- c("X1", "X", "...1", "Unnamed: 0", "unnamed: 0")

# if (names(train_pairs_ratings)[1] %in% index_like) {
#   train_pairs_ratings <- train_pairs_ratings |> select(-1)
# }

# train_pairs_ratings <- train_pairs_ratings |>
#   mutate(
#     rating = str_extract(out, "Answer=\\d+") |> str_remove("Answer=") |> as.numeric(),
#     rating_scaled = rating / 100
#   ) |>
#   filter(!is.na(rating_scaled))

# write_csv(train_pairs_ratings, out_file)


# PROCESS RATINGS -----------------------------------------------------------------------------------------------

library(readr)
library(stringr)
library(dplyr)

in_file  <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_ratings.csv"
out_file <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_rating_clean.csv"

# 1) Backup the original 50k file (once, timestamped)
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
backup_file <- str_replace(in_file, "\\.csv$", paste0("_FULL_50000_BACKUP_", ts, ".csv"))

if (!file.exists(backup_file)) {
  ok <- file.copy(in_file, backup_file, overwrite = FALSE)
  cat(sprintf("[%s] Backup created: %s (ok=%s)\n", Sys.time(), backup_file, ok)); flush.console()
} else {
  cat(sprintf("[%s] Backup already exists: %s\n", Sys.time(), backup_file)); flush.console()
}

# 2) Read ratings
train_pairs_ratings <- read_csv(in_file, show_col_types = FALSE)

# 3) Drop index-like first column if it exists
index_like <- c("X1", "X", "...1", "Unnamed: 0", "unnamed: 0")
if (names(train_pairs_ratings)[1] %in% index_like) {
  train_pairs_ratings <- train_pairs_ratings |> select(-1)
}

# 4) Robust parse of Answer formats:
#    Accepts: Answer=[85], Answer=85, Answer: 85  (case-insensitive)
#    Also drops "ERROR: ..." rows and blanks.
answer_pat <- regex("(?mi)^\\s*Answer\\s*[:=]\\s*\\[?(\\d{1,3})\\]?\\s*$")

train_pairs_clean <- train_pairs_ratings |>
  mutate(
    out = as.character(out),
    rating = str_match(out %||% "", answer_pat)[, 2] |> as.numeric(),
    rating_scaled = rating / 100
  ) |>
  # 5) Remove rows with missing/invalid ratings
  filter(!is.na(rating_scaled), rating >= 0, rating <= 100) |>
  # 6) Remove rows where the pair text is missing/empty (your "error rows that don't have content")
  mutate(
    text_i = as.character(text_i),
    text_j = as.character(text_j)
  ) |>
  filter(
    !is.na(text_i), !is.na(text_j),
    nchar(str_trim(text_i)) > 0,
    nchar(str_trim(text_j)) > 0
  )

cat(sprintf("[%s] Ratings input rows: %d\n", Sys.time(), nrow(train_pairs_ratings))); flush.console()
cat(sprintf("[%s] Ratings kept (clean): %d\n", Sys.time(), nrow(train_pairs_clean))); flush.console()

# 7) Write cleaned file (this is what SBERT training should use)
write_csv(train_pairs_clean, out_file)
cat(sprintf("[%s] Wrote cleaned ratings: %s\n", Sys.time(), out_file)); flush.console()




# # GENERATE NET -----

# torch = import("torch")
# sbert = import("sentence_transformers")
# hub = import("huggingface_hub")
# model = sbert$SentenceTransformer("dwulff/minilm-brl")

# context = "An article on behavioral agent-based modelling:\n\n"
# sem_emb = model$encode(paste0(context, data$text))
# rownames(sem_emb) = data$id

# saveRDS(sem_emb, "Mapping_landscape_ABM/Data/embs_1000/semantic_emb.RDS")


