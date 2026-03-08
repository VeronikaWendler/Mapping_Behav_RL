require(tidyverse)
library(reticulate)

Sys.setenv(
  PYTHONPATH = paste(
    "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/py_pkgs",
    Sys.getenv("PYTHONPATH"),
    sep = .Platform$path.sep
  )
)

Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required = TRUE)
print(py_config())

base_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000"
emb_path  <- file.path(base_dir, "data_tags_embedding.RDS")
dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)

tags <- read_csv(
  "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/tagging_1000/data_tags_v1.csv",
  show_col_types = FALSE
)

index_like <- c("X1", "X", "...1", "Unnamed: 0", "unnamed: 0")
if (names(tags)[1] %in% index_like) {
  tags <- tags %>% select(-1)
}

tags <- tags %>%
  mutate(tags = out |>
           str_extract("Answer=\\[[^\\]]+\\]") |>
           str_remove("^Answer=") |>
           str_remove_all("\\[|\\]") |>
           str_split(";") |>
           sapply(str_squish))

tags_tab <- tags$tags |> unlist() |> table() |> sort(decreasing = TRUE)
cat("Unique tags:", length(names(tags_tab)), "\n")

prompts <- paste0(names(tags_tab), " in behavioral agent-based modelling")

openai <- import("openai")
np <- import("numpy")

client <- openai$OpenAI(api_key = Sys.getenv("OPENAI_API_KEY"))

embed_batch <- function(texts, model = "text-embedding-3-large") {
  resp <- client$embeddings$create(
    model = model,
    input = texts
  )
  do.call(rbind, lapply(resp$data, function(x) x$embedding))
}

batch_size <- 512L
batches <- split(prompts, ceiling(seq_along(prompts) / batch_size))

emb_list <- vector("list", length(batches))

for (i in seq_along(batches)) {
  cat(sprintf("Embedding batch %d / %d ...\n", i, length(batches)))
  emb_list[[i]] <- embed_batch(batches[[i]])
}

tag_emb <- do.call(rbind, emb_list)
rownames(tag_emb) <- names(tags_tab)

saveRDS(tag_emb, emb_path)
cat("Saved embeddings to:", emb_path, "\n")







# require(tidyverse)
# library(reticulate)

# # ---- force reticulate to use your conda env ----
# Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
# use_condaenv("mapping_abm", required = TRUE)
# print(py_config())

# # ---- force ALL model/cache files to project storage, not home quota ----
# base_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000"
# hf_cache <- file.path(base_dir, "hf_cache")
# tmp_dir  <- file.path(base_dir, "tmp")
# model_dir <- file.path(base_dir, "qwen3_tag_model")
# emb_path  <- file.path(base_dir, "data_tags_embedding.RDS")

# dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)
# dir.create(hf_cache, recursive = TRUE, showWarnings = FALSE)
# dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)

# Sys.setenv(
#   HF_HOME = hf_cache,
#   TRANSFORMERS_CACHE = hf_cache,
#   HF_HUB_CACHE = file.path(hf_cache, "hub"),
#   HF_XET_CACHE = file.path(hf_cache, "xet"),
#   SENTENCE_TRANSFORMERS_HOME = hf_cache,
#   XDG_CACHE_HOME = hf_cache,
#   TMPDIR = tmp_dir,
#   TEMP = tmp_dir,
#   TMP = tmp_dir
# )
# cat("HF_HOME=", Sys.getenv("HF_HOME"), "\n")
# cat("MODEL_DIR=", model_dir, "\n")
# cat("EMB_PATH=", emb_path, "\n")

# require(remotes)
# Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

# if (!requireNamespace("memnet", quietly = TRUE)) {
#   remotes::install_github("dwulff/memnet")
# }
# library(memnet)

# tags <- read_csv(
#   "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/tagging_1000/data_tags_v1.csv",
#   show_col_types = FALSE
# )

# index_like <- c("X1", "X", "...1", "Unnamed: 0", "unnamed: 0")
# if (names(tags)[1] %in% index_like) {
#   tags <- tags %>% select(-1)
# }

# tags <- tags %>%
#   mutate(tags = out |>
#            str_extract("Answer=\\[[^\\]]+\\]") |>
#            str_remove("^Answer=") |>
#            str_remove_all("\\[|\\]") |>
#            str_split(";") |>
#            sapply(str_squish))

# tags_tab <- tags$tags |> unlist() |> table() |> sort(decreasing = TRUE)

# cat("Unique tags:", length(names(tags_tab)), "\n")

# torch <- import("torch")
# st <- import("sentence_transformers")

# device <- if (torch$cuda$is_available()) "cuda" else "cpu"
# cat("Using device:", device, "\n")

# # Load from saved local model if already present; otherwise download once
# if (dir.exists(model_dir) && length(list.files(model_dir, all.files = TRUE, no.. = TRUE)) > 0) {
#   cat("Loading existing local model from:", model_dir, "\n")
#   model <- st$SentenceTransformer(model_dir, device = device)
# } else {
#   cat("Downloading model from Hugging Face and saving locally...\n")
#   model <- st$SentenceTransformer("Qwen/Qwen3-Embedding-4B", device = device)
#   model$save(model_dir)
#   cat("Saved local model to:", model_dir, "\n")
# }

# prompts <- paste0(names(tags_tab), " in behavioral agent-based modelling")

# tag_emb <- model$encode(
#   prompts,
#   batch_size = as.integer(16),
#   show_progress_bar = TRUE,
#   convert_to_numpy = TRUE
# )

# rownames(tag_emb) <- names(tags_tab)

# saveRDS(tag_emb, emb_path)
# cat("Saved embeddings to:", emb_path, "\n")





#------
# EMBED ---

# tag_emb = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_tags_embedding.RDS")
# stopifnot(!is.null(rownames(tag_emb)))

# tag_cos = arma_cosine(tag_emb)
# rownames(tag_cos) = colnames(tag_cos) = rownames(tag_emb)

# tag_cos[tag_cos > 1] = 1
# tag_cos[tag_cos < -1] = -1
# tag_cos = 1-acos(tag_cos)/pi

# eps = 1/20^10
# cutoff = quantile(tag_cos[upper.tri(tag_cos)], .90) - eps

# tag_clust = fastcluster::hclust(as.dist(1 - tag_cos),
#                                  method = "complete")

# number_steps = sum(tag_clust$height <  (1 - cutoff))
# tag_clustering = cutree(tag_clust, k = nrow(tag_cos) - number_steps)
# names(tag_clustering) = rownames(tag_emb)

# tag_cliques = split(names(tag_clustering), tag_clustering)
# #clique_minimum = sapply(tag_cliques, function(x) tag_cos[x, x] |> min())


# #----
# # COMBINE ---

# tag_processed = 
#   tibble(tag = unlist(tag_cliques),
#          n = tags_tab[unlist(tag_cliques)] |> c(),
#          label = lapply(tag_cliques, function(x) {
#            n = tags_tab[x]
#            rep(x[which.max(n)], length(x))
#          }) |> unlist())

# tag_dict = tag_processed |> pull(label, tag)

# # tags = tags |> 
# #   mutate(tags_clean = lapply(tags, function(x) tag_dict[x])) |> 
# #   rename(tags_out = out)

# tags <- tags |>
#   mutate(tags_clean = lapply(.data$tags, function(x) unname(tag_dict[x]))) |>
#   rename(tags_out = out)


# data = read_csv("Mapping_landscape_ABM/Data/data_cleaned_filtered_4_1000.csv")

# data = data |> left_join(tags, by = "id")
# saveRDS(data, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged.RDS")