require(tidyverse)
require(reticulate)
#use_condaenv("form")

Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_python("~/apps/miniforge3/envs/mapping_abm/bin/python", required = TRUE)
use_condaenv("mapping_abm", required=TRUE)
print(py_config())

require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

tags = read_csv("Mapping_landscape_ABM/Data/tagging/data_tags_v1.csv") %>% 
  select(-1) %>% 
  mutate(tags = out |> str_extract("Answer=[:print:]+") |> str_remove("Answer=") |> str_remove_all("\\[|\\]") |> 
           str_split(";") |> sapply(str_squish))

tags_tab = tags$tags |> unlist() |> table() |> sort(decreasing = T)

# EMBED 
torch = import("torch")
st = import("sentence_transformers")

model = st$SentenceTransformer("Qwen/Qwen3-Embedding-4B", device = "mps")

prompts = paste0(names(tags_tab), " in behavioral reinforcement learning")

tag_emb = model$encode(prompts)
rownames(tag_emb) = names(tags_tab)
saveRDS(tag_emb, "Mapping_landscape_ABM/Data/tagging/data_tags_embedding.RDS")

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
