require(dbscan)
require(tidyverse)
require(reticulate)
Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required=TRUE)
print(py_config())
require(remotes)
Rcpp::sourceCpp("Mapping_landscape_RL/2_code/_helpers.cpp")

if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)


CODE_ROOT <- Sys.getenv("CODE_ROOT", unset = path.expand("~/projects/Mapping_Behav_RL"))
ABM_ROOT  <- Sys.getenv("ABM_ROOT",  unset = path.expand("~/projects/Mapping_landscape_ABM"))
DATA_ROOT <- Sys.getenv(
  "DATA_ROOT",
  unset = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL"
)

message("CODE_ROOT: ", CODE_ROOT)
message("ABM_ROOT:  ", ABM_ROOT)
message("DATA_ROOT: ", DATA_ROOT)

# -----------------------------
# PYTHON / RETICULATE
# -----------------------------
Sys.setenv(RETICULATE_CONDA = path.expand("~/apps/miniforge3/bin/conda"))
use_condaenv("mapping_abm", required = TRUE)
print(py_config())

# -----------------------------
# MEMNET INSTALL CHECK
# -----------------------------
if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)

# -----------------------------
# ENSURE OUTPUT DIRS EXIST
# -----------------------------
dir.create(file.path(DATA_ROOT, "1_data"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(DATA_ROOT, "1_data", "embs"), recursive = TRUE, showWarnings = FALSE)

# -----------------------------
# LOAD DATA
# -----------------------------
data <- readRDS(file.path(DATA_ROOT, "1_data", "data_cleaned_filtered_tagged.RDS")) %>%
  mutate(title_id = paste0(id, "_", str_to_lower(Title)))

author_emb     <- readRDS(file.path(DATA_ROOT, "1_data", "embs", "author_emb.RDS"))
references_emb <- readRDS(file.path(DATA_ROOT, "1_data", "embs", "references_emb.RDS"))
semantic_emb   <- readRDS(file.path(DATA_ROOT, "1_data", "embs", "semantic_emb.RDS"))

# -----------------------------
# COMBINE EMBEDDINGS
# -----------------------------
author_norms     <- apply(author_emb, 2, function(x) sqrt(sum(x^2)))
references_norms <- apply(references_emb, 2, function(x) sqrt(sum(x^2)))
semantic_norms   <- apply(semantic_emb, 2, function(x) sqrt(sum(x^2)))

author_emb     <- author_emb / (mean(author_norms) / mean(semantic_norms))
references_emb <- references_emb / (mean(references_norms) / mean(semantic_norms))

emb <- author_emb |>
  cbind(references_emb) |>
  cbind(semantic_emb)

colnames(emb) <- c(
  paste0("auth_", 1:384),
  paste0("ref_", 1:384),
  paste0("sem_", 1:384)
)
rownames(emb) <- data$id

saveRDS(
  emb,
  file.path(DATA_ROOT, "1_data", "embs", "combined_emb.RDS")
)

# -----------------------------
# NETWORK EXPORTS
# -----------------------------
author_net     <- embedR::er_compare_vectors(author_emb, metric = "arccos")
references_net <- embedR::er_compare_vectors(references_emb, metric = "arccos")
semantic_net   <- embedR::er_compare_vectors(semantic_emb, metric = "arccos")

author_lines <- sapply(
  1:nrow(author_net),
  function(x) paste0(author_net[x, ], collapse = ",")
)

references_lines <- sapply(
  1:nrow(references_net),
  function(x) paste0(references_net[x, ], collapse = ",")
)

semantic_lines <- sapply(
  1:nrow(semantic_net),
  function(x) paste0(semantic_net[x, ], collapse = ",")
)

write_lines(author_lines,     file.path(DATA_ROOT, "1_data", "embs", "author_net.txt"))
write_lines(references_lines, file.path(DATA_ROOT, "1_data", "embs", "references_net.txt"))
write_lines(semantic_lines,   file.path(DATA_ROOT, "1_data", "embs", "semantic_net.txt"))

# -----------------------------
# CLUSTERING / PACMAP
# -----------------------------
pacmap <- import("pacmap")

set.seed(42)
model <- pacmap$PaCMAP(
  n_components = as.integer(2),
  n_neighbors  = as.integer(50),
  MN_ratio     = 3,
  FP_ratio     = 10.0,
  distance     = "angular"
)

lyt <- py_to_r(model$fit_transform(emb))
lyt <- as.matrix(lyt)
colnames(lyt) <- c("lyt_x", "lyt_y")

# optionally save layout itself too
saveRDS(
  lyt,
  file.path(DATA_ROOT, "1_data", "embs", "pacmap_layout.RDS")
)

cluster <- hclust(dist(lyt), method = "complete")
clustering <- cutree(cluster, 30)

# make jitter once so on-screen and saved plot match
set.seed(42)
lyt_jittered <- lyt + matrix(rnorm(nrow(lyt) * 2, sd = 0.3), ncol = 2)

# -----------------------------
# PLOT TO SCREEN
# -----------------------------
plot(lyt_jittered, pch = 16, cex = 1, col = clustering + 3)
invisible(sapply(
  1:max(clustering),
  function(x) text(
    mean(lyt[clustering == x, 1]),
    mean(lyt[clustering == x, 2]),
    labels = x,
    col = "grey50"
  )
))

# -----------------------------
# SAVE PLOT TO PNG
# -----------------------------
png(
  filename = file.path(DATA_ROOT, "1_data", "cluster_plot.png"),
  width = 2400,
  height = 2400,
  res = 300
)
plot(lyt_jittered, pch = 16, cex = 1, col = clustering + 3)
invisible(sapply(
  1:max(clustering),
  function(x) text(
    mean(lyt[clustering == x, 1]),
    mean(lyt[clustering == x, 2]),
    labels = x,
    col = "grey50"
  )
))
dev.off()

# optional PDF version too
pdf(
  file = file.path(DATA_ROOT, "1_data", "cluster_plot.pdf"),
  width = 10,
  height = 10
)
plot(lyt_jittered, pch = 16, cex = 1, col = clustering + 3)
invisible(sapply(
  1:max(clustering),
  function(x) text(
    mean(lyt[clustering == x, 1]),
    mean(lyt[clustering == x, 2]),
    labels = x,
    col = "grey50"
  )
))
dev.off()

# -----------------------------
# SAVE CLUSTERED DATA
# -----------------------------
clusters <- as_tibble(lyt) |>
  mutate(
    country = clustering,
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
      country %in% c(29) ~ 10,
      TRUE ~ NA_real_
    ),
    id = data$id
  )

data <- data |> left_join(clusters, by = "id")

saveRDS(
  data,
  file.path(DATA_ROOT, "1_data", "data_cleaned_filtered_tagged_clustered.RDS")
)

message("Done.")
message("Saved combined embedding to: ", file.path(DATA_ROOT, "1_data", "embs", "combined_emb.RDS"))
message("Saved layout to: ", file.path(DATA_ROOT, "1_data", "embs", "pacmap_layout.RDS"))
message("Saved PNG plot to: ", file.path(DATA_ROOT, "1_data", "cluster_plot.png"))
message("Saved PDF plot to: ", file.path(DATA_ROOT, "1_data", "cluster_plot.pdf"))
message("Saved clustered data to: ", file.path(DATA_ROOT, "1_data", "data_cleaned_filtered_tagged_clustered.RDS"))













# data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/data_cleaned_filtered_tagged.RDS") %>% 
#   mutate(title_id = paste0(id, "_", str_to_lower(`Title`)))


# # COMBINE EMB -----------

# author_emb = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/embs/author_emb.RDS")
# references_emb = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/embs/references_emb.RDS")
# semantic_emb = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/embs/semantic_emb.RDS")

# author_norms = apply(author_emb, 2, function(x) sqrt(sum(x^2)))
# references_norms = apply(references_emb, 2, function(x) sqrt(sum(x^2)))
# semantic_norms = apply(semantic_emb, 2, function(x) sqrt(sum(x^2)))

# author_emb = author_emb / (mean(author_norms)/mean(semantic_norms))
# references_emb = references_emb / (mean(references_norms)/mean(semantic_norms))

# emb = author_emb |> cbind(references_emb) |> cbind(semantic_emb)
# colnames(emb) = c(paste0("auth_", 1:384), paste0("ref_", 1:384), paste0("sem_", 1:384))
# rownames(emb) = data$id
# saveRDS(emb, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/embs/combined_emb.RDS")

# author_net = embedR::er_compare_vectors(author_emb, metric="arccos")
# references_net = embedR::er_compare_vectors(references_emb, metric="arccos")
# semantic_net = embedR::er_compare_vectors(semantic_emb, metric="arccos")

# author_lines = sapply(1:nrow(author_net), function(x) paste0(author_net[i,], collapse=","))
# references_lines = sapply(1:nrow(references_net), function(x) paste0(references_net[i,], collapse=","))
# semantic_lines = sapply(1:nrow(semantic_net), function(x) paste0(semantic_net[i,], collapse=","))

# write_lines(author_lines, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/embs/author_net.txt")
# write_lines(references_lines, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/embs/references_net.txt")
# write_lines(semantic_lines, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/embs/semantic_net.txt")

# # CLUSTER ----------

# # pacmap <- import("pacmap")


# # set.seed(42)
# # model = pacmap$PaCMAP(n_components=as.integer(2), n_neighbors=as.integer(50), 
# #                       MN_ratio=3, FP_ratio=10.0, distance="angular")

# # #lyt = model$fit_transform(emb)
# # colnames(lyt) = c("lyt_x", "lyt_y")

# # cluster = hclust(dist(lyt), method = "complete")
# # clustering = cutree(cluster, 30)

# # plot(lyt + matrix(rnorm(nrow(lyt)*2, sd=.3),ncol=2), pch = 16, cex=1, col = clustering + 3)
# # sapply(1:max(clustering), function(x) text(mean(lyt[clustering==x,1]), mean(lyt[clustering==x,2]), label = x, col="grey50"))


# # CLUSTER ----------
# pacmap <- import("pacmap")

# set.seed(42)
# model = pacmap$PaCMAP(
#   n_components = as.integer(2),
#   n_neighbors = as.integer(50),
#   MN_ratio = 3,
#   FP_ratio = 10.0,
#   distance = "angular"
# )

# # lyt = model$fit_transform(emb)
# colnames(lyt) = c("lyt_x", "lyt_y")

# cluster = hclust(dist(lyt), method = "complete")
# clustering = cutree(cluster, 30)

# # make jitter once so the displayed and saved plot match
# lyt_jittered <- lyt + matrix(rnorm(nrow(lyt) * 2, sd = 0.3), ncol = 2)

# # plot to screen
# plot(lyt_jittered, pch = 16, cex = 1, col = clustering + 3)
# invisible(sapply(
#   1:max(clustering),
#   function(x) text(
#     mean(lyt[clustering == x, 1]),
#     mean(lyt[clustering == x, 2]),
#     labels = x,
#     col = "grey50"
#   )
# ))

# # save as PNG
# png(
#   "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/cluster_plot.png",
#   width = 2400,
#   height = 2400,
#   res = 300
# )
# plot(lyt_jittered, pch = 16, cex = 1, col = clustering + 3)
# invisible(sapply(
#   1:max(clustering),
#   function(x) text(
#     mean(lyt[clustering == x, 1]),
#     mean(lyt[clustering == x, 2]),
#     labels = x,
#     col = "grey50"
#   )
# ))
# dev.off()


# clusters = as_tibble(lyt) |> 
#   mutate(country = clustering,
#          continent = case_when(
#            country %in% c(11, 12, 30, 20, 14, 16, 4) ~ 1, 
#            country %in% c(9, 21, 15) ~ 2,
#            country %in% c(27) ~ 3,
#            country %in% c(28, 24, 8) ~ 4,
#            country %in% c(26, 25, 5, 10, 2) ~ 5,
#            country %in% c(19) ~ 6,
#            country %in% c(13) ~ 7,
#            country %in% c(1, 18, 7, 23, 3, 6, 22) ~ 8,
#            country %in% c(17) ~ 9,
#            country %in% c(29) ~ 10),
#          id = data$id)

# data = data |> left_join(clusters, by = "id")
# saveRDS(data, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Mapping_landscape_RL/1_data/data_cleaned_filtered_tagged_clustered.RDS")

