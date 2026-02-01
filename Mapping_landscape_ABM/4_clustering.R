require(dbscan)
require(tidyverse)
require(reticulate)
Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required=TRUE)
print(py_config())
require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)

data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged.RDS") %>% 
  mutate(title_id = paste0(id, "_", str_to_lower(`Title`)))


# COMBINE EMB ----------

author_emb = readRDS("Mapping_landscape_ABM/Data/embs_300/author_emb.RDS")
references_emb = readRDS("Mapping_landscape_ABM/Data/embs_300/references_emb.RDS")
semantic_emb = readRDS("Mapping_landscape_ABM/Data/embs_300/semantic_emb.RDS")

author_norms = apply(author_emb, 2, function(x) sqrt(sum(x^2)))
references_norms = apply(references_emb, 2, function(x) sqrt(sum(x^2)))
semantic_norms = apply(semantic_emb, 2, function(x) sqrt(sum(x^2)))

author_emb = author_emb / (mean(author_norms)/mean(semantic_norms))
references_emb = references_emb / (mean(references_norms)/mean(semantic_norms))

emb = author_emb |> cbind(references_emb) |> cbind(semantic_emb)
colnames(emb) = c(paste0("auth_", 1:384), paste0("ref_", 1:384), paste0("sem_", 1:384))
rownames(emb) = data$id
saveRDS(emb, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/combined_emb.RDS")

author_net = embedR::er_compare_vectors(author_emb, metric="arccos")
references_net = embedR::er_compare_vectors(references_emb, metric="arccos")
semantic_net = embedR::er_compare_vectors(semantic_emb, metric="arccos")

author_lines <- apply(author_net, 1, paste, collapse = ",")
references_lines <- apply(references_net, 1, paste, collapse = ",")
semantic_lines <- apply(semantic_net, 1, paste, collapse = ",")

out_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/nets"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_lines(author_lines,     file.path(out_dir, "author_net.txt"))
readr::write_lines(references_lines, file.path(out_dir, "references_net.txt"))
readr::write_lines(semantic_lines,   file.path(out_dir, "semantic_net.txt"))

# CLUSTER ----------

pacmap = import("pacmap")


set.seed(42)
model = pacmap$PaCMAP(n_components=as.integer(2), n_neighbors=as.integer(50), 
                      MN_ratio=3, FP_ratio=10.0, distance="angular")

lyt = model$fit_transform(emb)
colnames(lyt) = c("lyt_x", "lyt_y")

cluster = hclust(dist(lyt), method = "complete")
clustering = cutree(cluster, 30)

plot(lyt + matrix(rnorm(nrow(lyt)*2, sd=.3),ncol=2), pch = 16, cex=1, col = clustering + 3)
sapply(1:max(clustering), function(x) text(mean(lyt[clustering==x,1]), mean(lyt[clustering==x,2]), label = x, col="grey50"))


clusters = as_tibble(lyt) |> 
  mutate(country = clustering,
         continent = case_when(
           country %in% c(11, 12, 30, 20, 14, 16, 4) ~ 1, 
           country %in% c(9, 21, 15) ~ 2,
           country %in% c(27) ~ 3,
           country %in% c(28, 24, 8) ~ 4,
           country %in% c(26, 25, 5, 10, 2) ~ 5,
           country %in% c(19) ~ 6,
           country %in% c(13) ~ 7,
           country %in% c(1, 18, 7, 23, 3, 6, 22) ~ 8,
           country %in% c(17) ~ 9,
           country %in% c(29) ~ 10),
         id = data$id)

data = data |> left_join(clusters, by = "id")
saveRDS(data, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered.RDS")