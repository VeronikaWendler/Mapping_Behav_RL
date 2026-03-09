require(tidyverse)
require(reticulate)
Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required=TRUE)
print(py_config())
source("Mapping_landscape_ABM/_cubes.R")
require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)

require(tidyverse)
require(reticulate)

Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required = TRUE)
print(py_config())

pacmap <- import("pacmap")

# data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered_v2.RDS")
# emb = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/combined_emb.RDS")

# fig_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/figures/pacmap_tests"
# dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# semantic_block <- emb[, grepl("^sem_", colnames(emb)), drop = FALSE]

# run_map <- function(emb_mat, data, name,
#                     n_neighbors,
#                     MN_ratio,
#                     FP_ratio,
#                     jitter_sd = 0) {

#   set.seed(42)

#   model <- pacmap$PaCMAP(
#     n_components = as.integer(2),
#     n_neighbors = as.integer(n_neighbors),
#     MN_ratio = MN_ratio,
#     FP_ratio = FP_ratio,
#     distance = "angular"
#   )

#   coords_raw <- model$fit_transform(as.matrix(emb_mat))
#   coords <- reticulate::py_to_r(coords_raw)
#   coords <- as.data.frame(coords)
#   names(coords) <- c("x", "y")

#   plot_data <- bind_cols(data, coords)

#   if (jitter_sd > 0) {
#     set.seed(42)
#     plot_data <- plot_data |>
#       mutate(
#         x_plot = x + rnorm(n(), sd = jitter_sd),
#         y_plot = y + rnorm(n(), sd = jitter_sd)
#       )
#   } else {
#     plot_data <- plot_data |>
#       mutate(
#         x_plot = x,
#         y_plot = y
#       )
#   }

#   png(file.path(fig_dir, paste0(name, ".png")),
#       width = 8, height = 8, res = 300, units = "in",
#       bg = "white", type = "cairo-png")

#   p <- ggplot(plot_data, aes(x = x_plot, y = y_plot)) +
#     geom_point(shape = 21, fill = "black", color = "white", size = 1.2, stroke = 0.4) +
#     theme_void() +
#     theme(
#       plot.background = element_rect(fill = "white", colour = NA),
#       panel.background = element_rect(fill = "white", colour = NA)
#     ) +
#     ggtitle(name)

#   print(p)
#   dev.off()
# }

# run_map(
#   emb_mat = semantic_block,
#   data = data,
#   name = "map_nn30_mn1_fp5_nojitter",
#   n_neighbors = 30,
#   MN_ratio = 1.0,
#   FP_ratio = 5.0,
#   jitter_sd = 0
# )

# run_map(
#   emb_mat = semantic_block,
#   data = data,
#   name = "map_nn50_mn2_fp10_nojitter",
#   n_neighbors = 50,
#   MN_ratio = 2.0,
#   FP_ratio = 10.0,
#   jitter_sd = 0
# )

# run_map(
#   emb_mat = semantic_block,
#   data = data,
#   name = "map_nn100_mn2_fp20_nojitter",
#   n_neighbors = 100,
#   MN_ratio = 2.0,
#   FP_ratio = 20.0,
#   jitter_sd = 0
# )




# folders
data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered_MN_ratio3.RDS")
emb = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/combined_emb.RDS")

fig_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/figures/illustration_1000"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
cat("Saving figures to:", fig_dir, "\n")

author_net = arma_cosine(emb[,1:384]); author_net[is.na(author_net)] = 0
reference_net = arma_cosine(emb[,(1:384) + 384]); reference_net[is.na(reference_net)] = 0
semantic_net = arma_cosine(emb[,(1:384) + 384*2])

rownames(author_net) = rownames(reference_net) = rownames(semantic_net) = 
  data$title_id
colnames(author_net) = colnames(reference_net) = colnames(semantic_net) = 
  data$title_id

pacmap = import("pacmap")
set.seed(42)

model = pacmap$PaCMAP(
  n_components=as.integer(3),
  n_neighbors=as.integer(50), 
  MN_ratio=2,
  FP_ratio=10.0,
  distance="angular")

get_cube <- function(emb, col){

  clusters_raw <- model$fit_transform(as.matrix(emb))
  clusters <- reticulate::py_to_r(clusters_raw)
  clusters <- as.matrix(clusters)

  stopifnot(is.matrix(clusters))
  stopifnot(ncol(clusters) == 3)
  stopifnot(all(is.finite(clusters)))

  to01 <- function(x, f = 10) {
    rng <- max(x) - min(x)
    if (rng == 0) return(rep(f / 2, length(x)))
    (x - min(x)) / rng * f
  }

  clusters <- apply(clusters, 2, to01)

  angles <- c(30, 36.8, 23)
  d <- 50
  size <- 10
  sq <- (square(angles, d = d, size = size) |> apply(2, to01, f = 12) |> t() + c(1.5, -1, 0)) |> t()

  plot.new()
  plot.window(xlim = c(.15, 1.35) * 10, ylim = c(-.1, 1.1) * 10)
  segs(sq)

  cubes <- apply(clusters, 1, function(x) {
    list(square(angles, d = d, size = .25, orig = x[c(1,2,3)], scale = TRUE))
  }) |> lapply(function(x) x[[1]])

  pos <- sapply(cubes, function(x) max(x[,3]))
  cubes <- cubes[order(pos)]

  set.seed(42)
  cubes <- cubes[sample(length(cubes), min(1000, length(cubes)))]

  for(i in seq_along(cubes)) {
    faces(cubes[[i]], col = col, border = "white")
  }

  segs(sq, 2)
}

author_block    <- emb[, grepl("^auth_", colnames(emb)), drop = FALSE]
reference_block <- emb[, grepl("^ref_",  colnames(emb)), drop = FALSE]
semantic_block  <- emb[, grepl("^sem_",  colnames(emb)), drop = FALSE]


pdf(file.path(fig_dir, "author_MN_ratio_3.pdf"), width = 8, height = 8, bg = "white")
get_cube(author_block, viridis::mako(1, begin = .7))
dev.off()

pdf(file.path(fig_dir, "reference_MN_ratio_3.pdf"), width = 8, height = 8, bg = "white")
get_cube(reference_block, viridis::mako(1, begin = .7))
dev.off()

pdf(file.path(fig_dir, "semantic_MN_ratio_3.pdf"), width = 8, height = 8, bg = "white")
get_cube(semantic_block, viridis::mako(1, begin = .7))
dev.off()

pdf(file.path(fig_dir, "map_MN_ratio_3.pdf"), width = 8, height = 8, bg = "white")

p <- data |>
  ggplot(aes(x = lyt_x + rnorm(nrow(data), sd = .05),
             y = lyt_y + rnorm(nrow(data), sd = .05))) +
  geom_point(shape = 21, fill = "black", color = "white", size = 1.5, stroke = 0.5) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  )

print(p)
dev.off()


































# data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered.RDS")
# emb = readRDS("Mapping_landscape_ABM/Data/embs_300/combined_emb.RDS")

# author_net = arma_cosine(emb[,1:384]); author_net[is.na(author_net)] = 0
# reference_net = arma_cosine(emb[, 385:(384+322)]); reference_net[is.na(reference_net)] = 0
# semantic_net <- arma_cosine(emb[, 707:1090]); semantic_net[is.na(semantic_net)] <- 0

# rownames(author_net) = rownames(reference_net) = rownames(semantic_net) = 
#   data$title_id
# colnames(author_net) = colnames(reference_net) = colnames(semantic_net) = 
#   data$title_id

# pacmap <- import("pacmap")

# model = pacmap$PaCMAP(n_components=as.integer(3), n_neighbors=as.integer(100), 
#                       MN_ratio=2, FP_ratio=20.0, distance="angular")

# get_cube = function(emb, col){
  
#   clusters = model$fit_transform(emb)
  
#   to01 = function(x, f = 10) (x - min(x))/(max(x) - min(x)) * f
#   clusters = apply(clusters, 2, to01)
  
#   angles = c(30, 36.8, 23)
#   d = 50
#   size = 10
#   sq = (square(angles, d = d, size = size) |> apply(2, to01, f = 12) |> t() + c(1.5,-1,0)) |> t()
  
#   plot.new();plot.window(xlim=c(.15, 1.35) * 10, ylim=c(-.1, 1.1) * 10)
#   segs(sq)
  
#   cubes = apply(clusters, 1, function(x){
#     list(square(angles, d = d, size = .25, orig = x[c(1,2,3)], scale = TRUE))
#   }) |> lapply(function(x) x[[1]])
  
#   pos = sapply(cubes, function(x) max(x[,3]))
#   clusters = clusters[order(pos),]
#   cubes = cubes[order(pos)]
  
#   set.seed(42)
#   cubes = cubes[sample(length(cubes), 1000)]
  
#   for(i in 1:length(cubes)) {
#     faces(cubes[[i]], col = col, border = "white")
#   }

#   segs(sq,2)
#   }


# png("Mapping_landscape_ABM/Data/figures/illustration/author.png", width = 8, height = 8, res = 300, unit = "in", bg = "transparent")
# get_cube(emb[, 1:384], viridis::mako(1, begin = .7, alpha = .7))
# dev.off()

# png("Mapping_landscape_ABM/Data/figures/illustration/reference.png", width = 8, height = 8, res = 300, unit = "in", bg = "transparent")
# get_cube(emb[, 385:706], viridis::mako(1, begin = .5, alpha = .7))
# dev.off()

# png("Mapping_landscape_ABM/Data/figures/illustration/semantic.png", width = 8, height = 8, res = 300, unit = "in", bg = "transparent")
# get_cube(emb[, 707:1090], viridis::mako(1, begin = .3, alpha = .7))
# dev.off()

# png("Mapping_landscape_ABM/Data/figures/illustration/map.png",width=8, height=8, res = 300, unit = "in", bg = "transparent")
# data |> 
#   ggplot(aes(x = lyt_x + rnorm(nrow(data), sd = .3), y = lyt_y + rnorm(nrow(data), sd = .3))) + 
#   geom_point(pch=21, bg = "black", col = "white", cex = 1.5, stroke = .5) + 
#   theme_void()
# dev.off()