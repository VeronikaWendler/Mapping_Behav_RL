require(tidyverse)
library(reticulate)

Sys.setenv(
  HF_HOME = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/hf_cache",
  TRANSFORMERS_CACHE = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/hf_cache",
  HF_HUB_CACHE = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/hf_cache"
)
dir.create(Sys.getenv("HF_HOME"), recursive = TRUE, showWarnings = FALSE)

cat("HF_HOME=", Sys.getenv("HF_HOME"), "\n")
print(py_config())


require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")
if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)


tags <- read_csv(
  "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/tagging/data_tags_v1.csv",
  show_col_types = FALSE
)
index_like <- c("X1", "X", "...1", "Unnamed: 0", "unnamed: 0")
if (names(tags)[1] %in% index_like) {
  tags <- tags %>% select(-1)
}
tags <- tags %>%
  mutate(tags = out |>
           str_extract("Answer=[:print:]+") |>
           str_remove("Answer=") |>
           str_remove_all("\\[|\\]") |>
           str_split(";") |>
           sapply(str_squish))

tags_tab <- tags$tags |> unlist() |> table() |> sort(decreasing = TRUE)


# #------
# # old 
# torch = import("torch")
# st = import("sentence_transformers")

# device <- if (torch$cuda$is_available()) "cuda" else "cpu"
# cat("Using device:", device, "\n")
# model <- st$SentenceTransformer("Qwen/Qwen3-Embedding-4B", device = device)

# prompts = paste0(names(tags_tab), " in behavioral agent-based modelling")

# tag_emb <- model$encode(prompts, batch_size = as.integer(16), show_progress_bar = TRUE)
# rownames(tag_emb) = names(tags_tab)
# saveRDS(tag_emb, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_tags_embedding.RDS")


#------
# EMBED ---

tag_emb = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_tags_embedding.RDS")
stopifnot(!is.null(rownames(tag_emb)))

tag_cos = arma_cosine(tag_emb)
rownames(tag_cos) = colnames(tag_cos) = rownames(tag_emb)

tag_cos[tag_cos > 1] = 1
tag_cos[tag_cos < -1] = -1
tag_cos = 1-acos(tag_cos)/pi

eps = 1/20^10
cutoff = quantile(tag_cos[upper.tri(tag_cos)], .90) - eps

tag_clust = fastcluster::hclust(as.dist(1 - tag_cos),
                                 method = "complete")

number_steps = sum(tag_clust$height <  (1 - cutoff))
tag_clustering = cutree(tag_clust, k = nrow(tag_cos) - number_steps)
names(tag_clustering) = rownames(tag_emb)

tag_cliques = split(names(tag_clustering), tag_clustering)
#clique_minimum = sapply(tag_cliques, function(x) tag_cos[x, x] |> min())


#----
# COMBINE ---

tag_processed = 
  tibble(tag = unlist(tag_cliques),
         n = tags_tab[unlist(tag_cliques)] |> c(),
         label = lapply(tag_cliques, function(x) {
           n = tags_tab[x]
           rep(x[which.max(n)], length(x))
         }) |> unlist())

tag_dict = tag_processed |> pull(label, tag)

# tags = tags |> 
#   mutate(tags_clean = lapply(tags, function(x) tag_dict[x])) |> 
#   rename(tags_out = out)

tags <- tags |>
  mutate(tags_clean = lapply(.data$tags, function(x) unname(tag_dict[x]))) |>
  rename(tags_out = out)


data = read_csv("Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300.csv")

data = data |> left_join(tags, by = "id")
saveRDS(data, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged.RDS")