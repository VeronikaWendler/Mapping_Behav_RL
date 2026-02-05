# 7_overview_ABM_fixed.R ------------------------------------------------------
suppressPackageStartupMessages({
  library(tidyverse)
  library(tidytext)
  library(remotes)
  library(memnet)
})

source("2_code/_textboxes.R")
Rcpp::sourceCpp("2_code/_helpers.cpp")
if (!requireNamespace("memnet", quietly = TRUE)) remotes::install_github("dwulff/memnet")

data <- readRDS("Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.RDS")

# standardize year
if (!"year" %in% names(data) && "Year" %in% names(data)) data <- data %>% rename(year = Year)
if (!"year" %in% names(data)) data$year <- NA_integer_

# required cols
stopifnot(all(c("lyt_x","lyt_y","continent","country") %in% names(data)))
if (!"Source title" %in% names(data)) data$`Source title` <- NA_character_
if (!"tags_clean" %in% names(data)) data$tags_clean <- list(character())
if (!is.list(data$tags_clean)) data$tags_clean <- as.character(data$tags_clean) %>% str_split(";") %>% lapply(str_squish)

# continents
cont_levels <- sort(unique(data$continent))
K <- length(cont_levels)
cont_map <- tibble(continent = cont_levels, cont_idx = seq_len(K))
data <- data %>% left_join(cont_map, by = "continent")

colors <- tibble(
  cont_idx = 1:K,
  colors = viridis::mako(K, end = .8),
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .7)
)

# cluster sizes
cluster_counts <- data %>%
  count(country) %>%
  deframe()

# timeline limits
lims <- range(data$year, na.rm = TRUE)
if (!all(is.finite(lims))) lims <- c(2000, 2025)  # fallback

# country mapping (DO NOT assume 1..n)
countries <- sort(unique(data$country))
n_cluster <- length(countries)

# densities per cluster (handle missing years)
dens_list <- lapply(countries, function(cl) {
  yy <- data$year[data$country == cl]
  yy <- yy[is.finite(yy)]
  if (length(yy) < 2) return(list(x = seq(lims[1], lims[2], length.out = 256), y = rep(0, 256)))
  d <- density(yy, from = lims[1], to = lims[2], bw = 2, na.rm = TRUE)
  list(x = d$x, y = d$y)
})

dens_x <- do.call(rbind, lapply(dens_list, `[[`, "x"))
dens_y <- do.call(rbind, lapply(dens_list, `[[`, "y"))

# order clusters for display (by continent then median year)
clusters <- data %>%
  group_by(country, cont_idx) %>%
  summarise(
    mm = median(year, na.rm = TRUE),
    miny = suppressWarnings(min(year, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  arrange(cont_idx, mm, miny)

cluster_ord <- clusters$country
continent_ord <- clusters$cont_idx

# assign codes like 1A, 1B, ... within continent
clusters <- clusters %>%
  group_by(cont_idx) %>%
  mutate(code = paste0(cont_idx, LETTERS[seq_len(n())])) %>%
  ungroup()

codes <- clusters$code

# output
out_png <- "3_figures/ABM_cluster_overview.png"
dir.create("3_figures", showWarnings = FALSE, recursive = TRUE)

png(out_png, width = 14, height = 20, unit = "in", res = 200)

# layout widths
widths <- c(1.5, 0.7, 2.0, 2.0, 2.0)
first_col <- 1:min(15, n_cluster)
second_col <- if (n_cluster > 15) (16:n_cluster) else integer(0)

layout_mat <- matrix(0, nrow = max(length(first_col), length(second_col), 1),
                     ncol = length(widths) * 2 + 1)

# fill first column
for (i in seq_along(first_col)) {
  start_idx <- (i - 1) * length(widths) + 1
  layout_mat[i, 1:length(widths)] <- start_idx:(start_idx + length(widths) - 1)
}

# fill second column
if (length(second_col) > 0) {
  base <- max(layout_mat, na.rm = TRUE)
  for (i in seq_along(second_col)) {
    start_idx <- base + (i - 1) * length(widths) + 1
    layout_mat[i, (length(widths)+2):(2*length(widths)+1)] <- start_idx:(start_idx + length(widths) - 1)
  }
}

layout(layout_mat, widths = c(widths, 0.2, widths))
par(lheight = 0.78, family = "sans")

for (i in seq_len(n_cluster)) {

  cl <- cluster_ord[i]
  code <- codes[i]
  cont <- continent_ord[i]
  col <- colors$colors[cont]
  col_tr <- colors$colors_white2[cont]

  # index into density matrices
  di <- which(countries == cl)

  # 1) mini-map
  par(mar = c(0.5, 1.5, 0.5, 0.5))
  plot.new()
  plot.window(xlim = range(data$lyt_x, na.rm = TRUE),
              ylim = range(data$lyt_y, na.rm = TRUE))
  points(data$lyt_x, data$lyt_y, pch = 16, cex = 0.15, col = "grey90")

  same_cont <- data$country != cl & data$cont_idx == cont
  points(data$lyt_x[same_cont], data$lyt_y[same_cont], pch = 16, cex = 0.25, col = col_tr)

  current <- data$country == cl
  points(data$lyt_x[current], data$lyt_y[current], pch = 16, cex = 0.6, col = col)

  # 2) size
  par(mar = c(1, 0.5, 1, 0.5))
  plot.new()
  plot.window(xlim = c(-1, 1), ylim = c(-1, 1))
  text(0, 0.4, label = code, cex = 2.4, font = 2, col = col)
  text(0, -0.2, label = cluster_counts[as.character(cl)], cex = 1.8, font = 1)
  text(0, -0.55, label = "articles", cex = 1.2)

  # 3) timeline
  par(mar = c(5, 1.5, 1, 1.5))
  x <- dens_x[di, ]; y <- dens_y[di, ]
  x <- c(lims[1], x, tail(x, 1), lims[2])
  y <- c(0, y, 0, 0)

  plot.new()
  plot.window(xlim = lims, ylim = c(0, max(dens_y, na.rm = TRUE) * 1.05))
  polygon(x, y, col = col_tr, border = NA)
  lines(x, y, lwd = 2, col = col)
  lines(c(lims[1], lims[2]), c(0, 0))

  year_breaks <- seq(floor(lims[1]/10)*10, ceiling(lims[2]/10)*10, by = 10)
  axis(1, at = year_breaks, labels = year_breaks, cex.axis = 0.8, padj = -0.5)

  if (i %in% c(1, 16)) mtext("Year", side = 1, line = 2.5, font = 2, cex = 1.2)

  # 4) top tags
  par(mar = c(1, 0, 1, 0))
  tab <- data %>%
    filter(country == cl) %>%
    select(tags_clean) %>%
    unnest(tags_clean) %>%
    filter(!is.na(tags_clean), tags_clean != "") %>%
    count(tags_clean, sort = TRUE)

  generic_terms <- c("Agent-Based Modeling", "Agent-based model", "ABM", "Simulation", "Modeling")
  tab <- tab %>% filter(!tags_clean %in% generic_terms) %>% slice_head(n = 8)

  if (nrow(tab) > 0) {
    text_box(tab$tags_clean, sqrt(tab$n), base_cex = 1.0,
             text_align = "left", separator_padding = 0.03,
             top_whitespace = 0.1, square_size = c(0, 2.3, 0, 1),
             line_spacing_factor = 0.1)
  } else {
    plot.new(); plot.window(c(0,1), c(0,1))
    text(0.5, 0.5, "No tags", cex = 0.9, col = "gray50")
  }

  if (i %in% c(1, 16)) mtext("Key Topics", side = 3, cex = 1.2, font = 2, line = -0.7, adj = 0, at = 0)

  # 5) top journals
  par(mar = c(1, 0, 1, 0))
  journal <- data %>%
    filter(country == cl) %>%
    count(`Source title`, sort = TRUE) %>%
    slice_head(n = 6)

  if (nrow(journal) > 0) {
    text_box(journal$`Source title`, sqrt(journal$n), base_cex = 0.85,
             text_align = "left", separator_padding = 0.03,
             top_whitespace = 0.1, square_size = c(0, 2.3, 0, 1),
             line_spacing_factor = 0.1)
  } else {
    plot.new(); plot.window(c(0,1), c(0,1))
    text(0.5, 0.5, "No journal data", cex = 0.9, col = "gray50")
  }

  if (i %in% c(1, 16)) mtext("Top Journals", side = 3, cex = 1.2, font = 2, line = -0.7, adj = 0, at = 0)

  if (i == 15 && n_cluster > 15) {
    par(mar = c(0,0,0,0)); plot.new(); plot.window(c(0,1), c(0,1))
  }
}

dev.off()
cat("Cluster overview saved to: ", out_png, "\n", sep = "")
