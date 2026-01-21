require(tidyverse)
require(reticulate)

Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_python("~/apps/miniforge3/envs/mapping_abm/bin/python", required = TRUE)
use_condaenv("mapping_abm", required = TRUE)
print(py_config())

cat("TMPDIR=", Sys.getenv("TMPDIR"), "\n")
cat("HF_HOME=", Sys.getenv("HF_HOME"), "\n")

require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")
remotes::install_github("https://github.com/dwulff/memnet")

tags <- read_csv("Mapping_landscape_ABM/Data/tagging/data_tags_v1.csv", show_col_types = FALSE) %>%
  select(-1) %>%
  mutate(tags = out |> str_extract("Answer=[:print:]+") |> str_remove("Answer=") |>
           str_remove_all("\\[|\\]") |> str_split(";") |> sapply(str_squish))

tags_tab <- tags$tags |> unlist() |> table() |> sort(decreasing = TRUE)

torch <- import("torch")
st <- import("sentence_transformers")

model <- st$SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2", device = "cpu")

prompts <- paste0(names(tags_tab), " in behavioral reinforcement learning")

chunk_size <- as.integer(500)
n <- length(prompts)

chunk_id <- ((seq_len(n) - 1) %/% chunk_size) + 1
chunks <- split(seq_len(n), chunk_id)

emb_list <- vector("list", length(chunks))

for (i in seq_along(chunks)) {
  cat(sprintf("Embedding chunk %d / %d\n", i, length(chunks)))
  emb_list[[i]] <- model$encode(
    prompts[chunks[[i]]],
    batch_size = as.integer(32),
    show_progress_bar = TRUE
  )
}

tag_emb <- do.call(rbind, emb_list)
rownames(tag_emb) <- names(tags_tab)

scratch_out <- file.path(Sys.getenv("TMPDIR"), "data_tags_embedding.RDS")
saveRDS(tag_emb, scratch_out)
final_out <- "Mapping_landscape_ABM/Data/tagging/data_tags_embedding.RDS"
ok <- file.copy(scratch_out, final_out, overwrite = TRUE)
if (!ok) stop("file.copy() failed: could not copy embeddings back to /rds")
cat("Saved embeddings to:", final_out, "\n")



##########################
# # EMBED 
# torch = import("torch")
# st = import("sentence_transformers")

# model = st$SentenceTransformer("Qwen/Qwen3-Embedding-4B", device = "cpu")

# prompts = paste0(names(tags_tab), " in behavioral reinforcement learning")

# tag_emb = model$encode(prompts)
# rownames(tag_emb) = names(tags_tab)
# saveRDS(tag_emb, "Mapping_landscape_ABM/Data/tagging/data_tags_embedding.RDS")
##########################
# tag_emb = readRDS("1_data/tagging/data_tags_embedding.RDS")

# tag_cos = arma_cosine(tag_emb)
# rownames(tag_cos) = colnames(tag_cos) = rownames(tag_emb)

# tag_cos[tag_cos > 1] = 1
# tag_cos[tag_cos < -1] = -1
# tag_cos = 1-acos(tag_cos)/pi

# eps = 1/20**10
# cutoff = quantile(tag_cos[upper.tri(tag_cos)], .90) - eps

# tag_clust = fastcluster::hclust(as.dist(1 - tag_cos),
#                                  method = "complete")

# number_steps = sum(tag_clust$height <  (1 - cutoff))
# tag_clustering = cutree(tag_clust, k = nrow(tag_cos) - number_steps)
# names(tag_clustering) = rownames(tag_emb)

# tag_cliques = split(names(tag_clustering), tag_clustering)
# #clique_minimum = sapply(tag_cliques, function(x) tag_cos[x, x] |> min())

# # COMBINE ---

# tag_processed = 
#   tibble(tag = unlist(tag_cliques),
#          n = tags_tab[unlist(tag_cliques)] |> c(),
#          label = lapply(tag_cliques, function(x) {
#            n = tags_tab[x]
#            rep(x[which.max(n)], length(x))
#          }) |> unlist())

# tag_dict = tag_processed |> pull(label, tag)

# tags = tags |> 
#   mutate(tags_clean = lapply(tags, function(x) tag_dict[x])) |> 
#   rename(tags_out = out)

# data = read_csv("1_data/data_cleaned_filtered.csv")

# data = data |> left_join(tags, by = "id")
# saveRDS(data, "1_data/data_cleaned_filtered_tagged.RDS")
