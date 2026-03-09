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



# -----------------------------
# Load data
# -----------------------------
data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered_MN_ratio2.RDS")
emb  = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/combined_emb.RDS")

fig_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/figures/illustration_1000_try2"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
cat("Saving figures to:", fig_dir, "\n")

stopifnot(nrow(emb) == nrow(data))

# -----------------------------
# Split embedding blocks
# -----------------------------
author_block    <- emb[, grepl("^auth_", colnames(emb)), drop = FALSE]
reference_block <- emb[, grepl("^ref_",  colnames(emb)), drop = FALSE]
semantic_block  <- emb[, grepl("^sem_",  colnames(emb)), drop = FALSE]

# -----------------------------
# Import PaCMAP
# -----------------------------
pacmap <- import("pacmap")
set.seed(42)

# -----------------------------
# 3D model for cube illustrations
# -----------------------------
model3d <- pacmap$PaCMAP(
  n_components = as.integer(3),
  n_neighbors  = as.integer(50),
  MN_ratio     = 2,
  FP_ratio     = 10.0,
  distance     = "angular"
)

get_cube <- function(emb_mat, col) {
  clusters_raw <- model3d$fit_transform(as.matrix(emb_mat))
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
  sq <- (square(angles, d = d, size = size) |>
           apply(2, to01, f = 12) |>
           t() + c(1.5, -1, 0)) |>
    t()

  plot.new()
  plot.window(xlim = c(.15, 1.35) * 10, ylim = c(-.1, 1.1) * 10)
  segs(sq)

  cubes <- apply(clusters, 1, function(x) {
    list(square(angles, d = d, size = .25, orig = x[c(1, 2, 3)], scale = TRUE))
  }) |>
    lapply(function(x) x[[1]])

  pos <- sapply(cubes, function(x) max(x[, 3]))
  cubes <- cubes[order(pos)]

  set.seed(42)
  cubes <- cubes[sample(length(cubes), min(1000, length(cubes)))]

  for (i in seq_along(cubes)) {
    faces(cubes[[i]], col = col, border = "white")
  }

  segs(sq, 2)
}

# -----------------------------
# Save cube illustrations
# -----------------------------
pdf(file.path(fig_dir, "author_MN_ratio_2.pdf"), width = 8, height = 8, bg = "white")
get_cube(author_block, viridis::mako(1, begin = .7))
dev.off()

pdf(file.path(fig_dir, "reference_MN_ratio_2.pdf"), width = 8, height = 8, bg = "white")
get_cube(reference_block, viridis::mako(1, begin = .5))
dev.off()

pdf(file.path(fig_dir, "semantic_MN_ratio_2.pdf"), width = 8, height = 8, bg = "white")
get_cube(semantic_block, viridis::mako(1, begin = .3))
dev.off()

# -----------------------------
# 2D semantic-only map
# -----------------------------
model2d <- pacmap$PaCMAP(
  n_components = as.integer(2),
  n_neighbors  = as.integer(50),
  MN_ratio     = 2,
  FP_ratio     = 10.0,
  distance     = "angular"
)

lyt2_raw <- model2d$fit_transform(as.matrix(semantic_block))
lyt2 <- reticulate::py_to_r(lyt2_raw)
lyt2 <- as.matrix(lyt2)

stopifnot(is.matrix(lyt2))
stopifnot(ncol(lyt2) == 2)
stopifnot(all(is.finite(lyt2)))

colnames(lyt2) <- c("lyt_x_sem", "lyt_y_sem")

plot_data <- bind_cols(data, as.data.frame(lyt2))

# -----------------------------
# 3) Detect semantic regions from the semantic map
# -----------------------------
require(dbscan)

coords_sem <- plot_data |>
  select(lyt_x_sem, lyt_y_sem) |>
  as.matrix()

# Tune minPts if needed: 20, 25, 30 are sensible starting points
sem_cl <- dbscan::hdbscan(coords_sem, minPts = 25)

plot_data <- plot_data |>
  mutate(semantic_region = sem_cl$cluster)

# Save with semantic-region assignments
saveRDS(plot_data, file.path(fig_dir, "data_semantic_map_with_regions_MN_ratio_2.RDS"))

# -----------------------------
# 4) Plot semantic regions
# -----------------------------
pdf(file.path(fig_dir, "map_semantic_only_regions_hdbscan.pdf"),
    width = 8, height = 8, bg = "white")

p_regions <- plot_data |>
  ggplot(aes(x = lyt_x_sem, y = lyt_y_sem, fill = factor(semantic_region))) +
  geom_point(shape = 21, color = "white", size = 1.1, stroke = 0.2) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  ) +
  guides(fill = guide_legend(title = "Semantic region"))

print(p_regions)
dev.off()

# -----------------------------
# 5) Find representative papers per semantic region
# -----------------------------
region_centroids <- plot_data |>
  filter(semantic_region != 0) |>
  group_by(semantic_region) |>
  summarise(
    cx = mean(lyt_x_sem),
    cy = mean(lyt_y_sem),
    n_papers = n(),
    .groups = "drop"
  )

# Detect title column robustly
title_col <- c("Title", "title", "paper_title")[
  c("Title", "title", "paper_title") %in% names(plot_data)
][1]

if (is.na(title_col)) stop("Could not find a title column in data.")

rep_titles <- plot_data |>
  filter(semantic_region != 0) |>
  left_join(region_centroids, by = "semantic_region") |>
  mutate(
    dist_to_centroid = sqrt((lyt_x_sem - cx)^2 + (lyt_y_sem - cy)^2)
  ) |>
  group_by(semantic_region) |>
  arrange(dist_to_centroid, .by_group = TRUE) |>
  slice_head(n = 10) |>
  ungroup() |>
  select(
    semantic_region,
    id,
    title = all_of(title_col),
    dist_to_centroid
  )

readr::write_csv(rep_titles, file.path(fig_dir, "semantic_region_representative_titles.csv"))

# -----------------------------
# 6) Extract top tags per semantic region
# -----------------------------
# Try to find a tags column
tag_col <- c("tags_clean", "tags", "tag", "keywords")[
  c("tags_clean", "tags", "tag", "keywords") %in% names(plot_data)
][1]

if (!is.na(tag_col)) {

  tags_long <- plot_data |>
    filter(semantic_region != 0) |>
    select(id, semantic_region, all_of(tag_col)) |>
    mutate(tag_raw = .data[[tag_col]]) |>
    mutate(
      tag_raw = purrr::map(tag_raw, function(x) {
        if (is.null(x)) return(character(0))
        if (is.list(x)) return(unlist(x))
        if (length(x) > 1) return(as.character(x))
        x <- as.character(x)
        # split strings like "a; b; c" or "a, b, c"
        unlist(strsplit(x, "\\s*[,;|]\\s*"))
      })
    ) |>
    tidyr::unnest(tag_raw) |>
    mutate(
      tag_raw = stringr::str_trim(stringr::str_to_lower(tag_raw))
    ) |>
    filter(tag_raw != "")

  # remove generic ABM terms that don't help labeling
  generic_tags <- c(
    "agent-based model",
    "agent-based models",
    "agent-based simulation",
    "agent-based simulations",
    "multi-agent system",
    "multi-agent systems",
    "multi-agent simulation",
    "multi-agent simulations",
    "complex adaptive systems",
    "social simulation",
    "simulation",
    "computational model",
    "computational models"
  )

  top_tags <- tags_long |>
    filter(!tag_raw %in% generic_tags) |>
    count(semantic_region, tag_raw, sort = TRUE) |>
    group_by(semantic_region) |>
    slice_head(n = 15) |>
    ungroup()

  readr::write_csv(top_tags, file.path(fig_dir, "semantic_region_top_tags.csv"))

  # -----------------------------
  # 7) Simple auto-label suggestions from top tags
  # -----------------------------
  auto_labels <- top_tags |>
    group_by(semantic_region) |>
    summarise(
      label_auto = paste(head(tag_raw, 3), collapse = " / "),
      .groups = "drop"
    ) |>
    left_join(region_centroids, by = "semantic_region")

  readr::write_csv(auto_labels, file.path(fig_dir, "semantic_region_auto_labels.csv"))

    # -----------------------------
  # 7b) Build a cleaner legend table
  # -----------------------------
  top_tags_summary <- top_tags |>
    group_by(semantic_region) |>
    summarise(
      top_tags_5 = paste(head(tag_raw, 5), collapse = " | "),
      .groups = "drop"
    )

  region_legend <- region_centroids |>
    left_join(auto_labels |> select(semantic_region, label_auto), by = "semantic_region") |>
    left_join(top_tags_summary, by = "semantic_region") |>
    arrange(semantic_region)

  readr::write_csv(region_legend, file.path(fig_dir, "semantic_region_legend.csv"))
  saveRDS(region_legend, file.path(fig_dir, "semantic_region_legend.RDS"))

  # plain text legend
  legend_lines <- region_legend |>
    mutate(
      line = paste0(
        "Region ", semantic_region,
        " (n=", n_papers, "): ",
        label_auto,
        " || Top tags: ", top_tags_5
      )
    ) |>
    pull(line)

  readr::write_lines(legend_lines, file.path(fig_dir, "semantic_region_legend.txt"))

  # -----------------------------
  # 7c) Plot map with numbers only
  # -----------------------------
  pdf(file.path(fig_dir, "map_semantic_only_regions_numbered.pdf"),
      width = 8, height = 8, bg = "white")

  p_regions_num <- plot_data |>
    ggplot(aes(x = lyt_x_sem, y = lyt_y_sem, fill = factor(semantic_region))) +
    geom_point(shape = 21, color = "white", size = 1.0, stroke = 0.15) +
    geom_label(
      data = region_legend,
      aes(x = cx, y = cy, label = semantic_region),
      inherit.aes = FALSE,
      size = 3.5,
      label.size = 0.2,
      fill = "white"
    ) +
    theme_void() +
    theme(
      plot.background = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "white", colour = NA)
    ) +
    guides(fill = guide_legend(title = "Semantic region"))

  print(p_regions_num)
  dev.off()

  # plot with auto labels
  # pdf(file.path(fig_dir, "map_semantic_only_regions_labeled_auto.pdf"),
  #     width = 8, height = 8, bg = "white")

  # p_regions_lab <- plot_data |>
  #   ggplot(aes(x = lyt_x_sem, y = lyt_y_sem, fill = factor(semantic_region))) +
  #   geom_point(shape = 21, color = "white", size = 1.0, stroke = 0.15) +
  #   geom_text(
  #     data = auto_labels,
  #     aes(x = cx, y = cy, label = label_auto),
  #     inherit.aes = FALSE,
  #     size = 3.5
  #   ) +
  #   theme_void() +
  #   theme(
  #     plot.background = element_rect(fill = "white", colour = NA),
  #     panel.background = element_rect(fill = "white", colour = NA)
  #   ) +
  #   guides(fill = guide_legend(title = "Semantic region"))

  # print(p_regions_lab)
  # dev.off()

} else {
  warning("No tags column found. Skipping tag summaries and auto labels.")
}

# -----------------------------
# 8) Save region sizes
# -----------------------------
region_sizes <- plot_data |>
  count(semantic_region, sort = TRUE)

readr::write_csv(region_sizes, file.path(fig_dir, "semantic_region_sizes.csv"))

cat("Saved semantic-region outputs:\n")
cat(" - data_semantic_map_with_regions_MN_ratio_2.RDS\n")
cat(" - map_semantic_only_regions_hdbscan.pdf\n")
cat(" - semantic_region_representative_titles.csv\n")
cat(" - semantic_region_sizes.csv\n")
cat(" - semantic_region_top_tags.csv (if tag column found)\n")
cat(" - semantic_region_auto_labels.csv (if tag column found)\n")
cat(" - map_semantic_only_regions_labeled_auto.pdf (if tag column found)\n")

# Save coordinates too, so you can reuse them later
saveRDS(plot_data, file.path(fig_dir, "data_semantic_map_coords_MN_ratio_2.RDS"))

# Raw semantic-only map, no jitter
pdf(file.path(fig_dir, "map_semantic_only_MN_ratio_2_nojitter.pdf"),
    width = 8, height = 8, bg = "white")

p1 <- plot_data |>
  ggplot(aes(x = lyt_x_sem, y = lyt_y_sem)) +
  geom_point(shape = 21, fill = "black", color = "white", size = 1.5, stroke = 0.5) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  )

print(p1)
dev.off()

# Raw semantic-only map, tiny jitter
set.seed(42)
plot_data_jit <- plot_data |>
  mutate(
    lyt_x_sem_jit = lyt_x_sem + rnorm(n(), sd = .02),
    lyt_y_sem_jit = lyt_y_sem + rnorm(n(), sd = .02)
  )

pdf(file.path(fig_dir, "map_semantic_only_MN_ratio_2_tinyjitter.pdf"),
    width = 8, height = 8, bg = "white")

p2 <- plot_data_jit |>
  ggplot(aes(x = lyt_x_sem_jit, y = lyt_y_sem_jit)) +
  geom_point(shape = 21, fill = "black", color = "white", size = 1.5, stroke = 0.5) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  )

print(p2)
dev.off()

# Semantic-only map colored by current continent
pdf(file.path(fig_dir, "map_semantic_only_MN_ratio_2_by_continent.pdf"),
    width = 8, height = 8, bg = "white")

p3 <- plot_data |>
  ggplot(aes(x = lyt_x_sem, y = lyt_y_sem, fill = factor(continent))) +
  geom_point(shape = 21, color = "white", size = 1.2, stroke = 0.25) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  ) +
  guides(fill = guide_legend(title = "Continent"))

print(p3)
dev.off()

# Semantic-only map colored by current country
pdf(file.path(fig_dir, "map_semantic_only_MN_ratio_2_by_country.pdf"),
    width = 8, height = 8, bg = "white")

p4 <- plot_data |>
  ggplot(aes(x = lyt_x_sem, y = lyt_y_sem, fill = factor(country))) +
  geom_point(shape = 21, color = "white", size = 1.0, stroke = 0.15) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  ) +
  guides(fill = "none")

print(p4)
dev.off()

cat("Done.\n")
cat("Created files:\n")
cat(" - author_MN_ratio_2.pdf\n")
cat(" - reference_MN_ratio_2.pdf\n")
cat(" - semantic_MN_ratio_2.pdf\n")
cat(" - map_semantic_only_MN_ratio_2_nojitter.pdf\n")
cat(" - map_semantic_only_MN_ratio_2_tinyjitter.pdf\n")
cat(" - map_semantic_only_MN_ratio_2_by_continent.pdf\n")
cat(" - map_semantic_only_MN_ratio_2_by_country.pdf\n")
cat(" - data_semantic_map_coords_MN_ratio_2.RDS\n")






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




# # folders
# data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered_MN_ratio2.RDS")
# emb = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/combined_emb.RDS")

# fig_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/figures/illustration_1000"
# dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
# cat("Saving figures to:", fig_dir, "\n")

# author_net = arma_cosine(emb[,1:384]); author_net[is.na(author_net)] = 0
# reference_net = arma_cosine(emb[,(1:384) + 384]); reference_net[is.na(reference_net)] = 0
# semantic_net = arma_cosine(emb[,(1:384) + 384*2])

# rownames(author_net) = rownames(reference_net) = rownames(semantic_net) = 
#   data$title_id
# colnames(author_net) = colnames(reference_net) = colnames(semantic_net) = 
#   data$title_id

# pacmap = import("pacmap")
# set.seed(42)

# model = pacmap$PaCMAP(
#   n_components=as.integer(3),
#   n_neighbors=as.integer(50), 
#   MN_ratio=2,
#   FP_ratio=10.0,
#   distance="angular")

# get_cube <- function(emb, col){

#   clusters_raw <- model$fit_transform(as.matrix(emb))
#   clusters <- reticulate::py_to_r(clusters_raw)
#   clusters <- as.matrix(clusters)

#   stopifnot(is.matrix(clusters))
#   stopifnot(ncol(clusters) == 3)
#   stopifnot(all(is.finite(clusters)))

#   to01 <- function(x, f = 10) {
#     rng <- max(x) - min(x)
#     if (rng == 0) return(rep(f / 2, length(x)))
#     (x - min(x)) / rng * f
#   }

#   clusters <- apply(clusters, 2, to01)

#   angles <- c(30, 36.8, 23)
#   d <- 50
#   size <- 10
#   sq <- (square(angles, d = d, size = size) |> apply(2, to01, f = 12) |> t() + c(1.5, -1, 0)) |> t()

#   plot.new()
#   plot.window(xlim = c(.15, 1.35) * 10, ylim = c(-.1, 1.1) * 10)
#   segs(sq)

#   cubes <- apply(clusters, 1, function(x) {
#     list(square(angles, d = d, size = .25, orig = x[c(1,2,3)], scale = TRUE))
#   }) |> lapply(function(x) x[[1]])

#   pos <- sapply(cubes, function(x) max(x[,3]))
#   cubes <- cubes[order(pos)]

#   set.seed(42)
#   cubes <- cubes[sample(length(cubes), min(1000, length(cubes)))]

#   for(i in seq_along(cubes)) {
#     faces(cubes[[i]], col = col, border = "white")
#   }

#   segs(sq, 2)
# }

# author_block    <- emb[, grepl("^auth_", colnames(emb)), drop = FALSE]
# reference_block <- emb[, grepl("^ref_",  colnames(emb)), drop = FALSE]
# semantic_block  <- emb[, grepl("^sem_",  colnames(emb)), drop = FALSE]


# pdf(file.path(fig_dir, "author_MN_ratio_2.pdf"), width = 8, height = 8, bg = "white")
# get_cube(author_block, viridis::mako(1, begin = .7))
# dev.off()

# pdf(file.path(fig_dir, "reference_MN_ratio_2.pdf"), width = 8, height = 8, bg = "white")
# get_cube(reference_block, viridis::mako(1, begin = .7))
# dev.off()

# pdf(file.path(fig_dir, "semantic_MN_ratio_2.pdf"), width = 8, height = 8, bg = "white")
# get_cube(semantic_block, viridis::mako(1, begin = .7))
# dev.off()

# pdf(file.path(fig_dir, "map_MN_ratio_2.pdf"), width = 8, height = 8, bg = "white")

# p <- data |>
#   ggplot(aes(x = lyt_x + rnorm(nrow(data), sd = .05),
#              y = lyt_y + rnorm(nrow(data), sd = .05))) +
#   geom_point(shape = 21, fill = "black", color = "white", size = 1.5, stroke = 0.5) +
#   theme_void() +
#   theme(
#     plot.background = element_rect(fill = "white", colour = NA),
#     panel.background = element_rect(fill = "white", colour = NA)
#   )

# print(p)
# dev.off()


































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