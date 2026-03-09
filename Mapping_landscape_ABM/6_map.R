require(tidyverse)
require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("https://github.com/dwulff/memnet")
}
library(memnet)

data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered_MN_ratio2.RDS")

set.seed(42)
data = data |> 
  mutate(
    lyt_x_jit = lyt_x + rnorm(n(), sd = .05),
    lyt_y_jit = lyt_y + rnorm(n(), sd = .05)
  )

fig_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/figures/illustration_1000"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

png(file.path(fig_dir, "cluster_map_v2.png"),
    width = 8, height = 4.8, units = "in", res = 300, bg = "white", type = "cairo-png")

continents = tibble(
  continent = 1:6,
  order = c(3, 2, 6, 5, 4, 1),
  number = 1:6,
  colors = viridis::mako(6, end = .8)[order],
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .75)
)

centroids = data %>% 
  group_by(continent) %>% 
  summarize(
    lyt_x = mean(lyt_x),
    lyt_y = mean(lyt_y),
    .groups = "drop"
  ) %>% 
  mutate(
    lab_x = lyt_x + c(-2, 2, 3, -2, 2, -3),
    lab_y = lyt_y + c(4, 3, -1, -3, -4, 2),
    adj = c(.5, 0, 0, 1, 0, 1)
  )

continents = continents %>% 
  left_join(centroids, by = "continent") %>% 
  mutate(labels = c(
    "General ABM,\nTheory & Complexity",
    "Organizations,\nSupply Chains\n& Innovation",
    "Energy,\nElectricity\n& Low-Carbon Systems",
    "Finance,\nMacroeconomics\n& Strategic Markets",
    "Social Behavior,\nNetworks\n& Game Dynamics",
    "Environment,\nLand, Water\n& Socio-Ecological Policy"
  ))

xlim = range(data$lyt_x)
ylim = range(data$lyt_y)

par(mar = c(0, 0, 0, 0))
plot.new()
plot.window(xlim = xlim * c(1.1, 1.1), ylim = ylim * c(1, 1.2))

for(i in 1:nrow(continents)) {

  data_i = data %>% 
    filter(continent == i) %>% 
    mutate(
      lyt_x = lyt_x + runif(n(), -.3, .3),
      lyt_y = lyt_y + runif(n(), -.3, .3)
    )

  hull = concaveman::concaveman(
    cbind(data_i$lyt_x, data_i$lyt_y),
    concavity = 2,
    length_threshold = 2
  )

  hull[,1] = round(round(hull[,1] * 2, 1) / 2, 2)
  hull[,2] = round(round(hull[,2] * 2, 1) / 2, 2)

  rx = range(hull[,1])
  ry = range(hull[,2])

  grid = expand.grid(
    x = seq(rx[1], rx[2], .05) %>% round(2),
    y = seq(ry[1], ry[2], .05) %>% round(2)
  ) %>% as.matrix()

  index = expand.grid(
    xi = 1:length(seq(rx[1], rx[2], .05)),
    yi = 1:length(seq(ry[1], ry[2], .05))
  ) %>% as.matrix()

  points = matrix(nrow = nrow(grid), ncol = 2, dimnames = list(NULL, c("in", "cntry")))

  for(k in 1:nrow(grid)) {
    pt = grid[k, ]
    points[k,1] = pnpoly(pt, hull)
    dists = sqrt((data_i$lyt_x - pt[1])^2 + (data_i$lyt_y - pt[2])^2)
    points[k,2] = data_i$country[which.min(dists)]
  }

  points = cbind(index, cbind(grid, points))
  points = points[points[, "in"] > 0, ]

  uni_countries = unique(data_i$country)
  col = continents$colors_white2[data_i$continent[1]]

  for(j in 1:length(uni_countries)) {
    points_cntry = points[points[, "cntry"] == uni_countries[j], c("x", "y")]

    border = c()
    for(k in 1:nrow(points_cntry)) {
      pt = points_cntry[k, c("x", "y")]
      dists = (abs(points_cntry[, "x"] - pt[1]) + abs(points_cntry[, "y"] - pt[2])) / 2
      border[k] = ifelse(sum(round(dists, 2) == .05) == 8, 0, 1)
    }

    w = .05
    rect(
      points_cntry[,1] - w/2, points_cntry[,2] - w/2,
      points_cntry[,1] + w/2, points_cntry[,2] + w/2,
      col = ifelse(border, "white", col),
      border = NA
    )
  }

  points(
    data_i$lyt_x_jit,
    data_i$lyt_y_jit,
    bg = continents$colors[data_i$continent],
    col = continents$colors_white[data_i$continent],
    pch = 21, cex = .2, lwd = .1
  )
}

for(i in 1:nrow(continents)) {
  continents_i = continents %>% slice(i)
  text(
    continents_i$lab_x, continents_i$lab_y,
    labels = paste0(continents_i$labels, " (", continents_i$number, ")"),
    cex = .9,
    adj = continents_i$adj,
    col = continents_i$colors,
    font = 1
  )
}

dev.off()

















# require(tidyverse)
# require(remotes)
# require(concaveman)
# require(viridis)
# require(tidyr)
# require(stringr)
# require(tidytext)

# Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

# if (!requireNamespace("memnet", quietly = TRUE)) {
#   remotes::install_github("dwulff/memnet")
# }
# library(memnet)

# # ---------------------------
# # Load data
# # ---------------------------
# data <- readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.RDS")

# stopifnot("tags_clean" %in% names(data))

# generic_terms <- c(
#   "Agent-Based Modeling", "Agent-based model", "Agent-based modeling",
#   "ABM", "Simulation", "Modeling"
# )

# # Turn list-column tags_clean into long format: one row per (paper, country, tag)
# tags_long <- data %>%
#   select(country, continent, tags_clean) %>%
#   tidyr::unnest(tags_clean) %>%
#   mutate(tags_clean = stringr::str_squish(tags_clean)) %>%
#   filter(!is.na(tags_clean), tags_clean != "") %>%
#   filter(!tags_clean %in% generic_terms)

# # TF-IDF per country cluster (across the whole dataset)
# country_tag_tfidf <- tags_long %>%
#   count(country, tags_clean, sort = FALSE) %>%
#   bind_tf_idf(term = tags_clean, document = country, n = n) %>%
#   arrange(country, desc(tf_idf))

# # Build a short label per country cluster: top 2–3 tags by tf-idf
# country_names <- country_tag_tfidf %>%
#   group_by(country) %>%
#   slice_max(tf_idf, n = 3, with_ties = FALSE) %>%
#   summarise(
#     country_name = paste(tags_clean, collapse = " / "),
#     .groups = "drop"
#   )


# cat("nrow:", nrow(data), " ncol:", ncol(data), "\n")
# print(names(data))

# cat("Has year:", "year" %in% names(data), "\n")
# cat("Has Year:", "Year" %in% names(data), "\n")
# year_like <- grep("year|Year|PY|pub|date|Date", names(data), value = TRUE)
# print(year_like)

# if ("year" %in% names(data)) {
#   cat("year class:", class(data$year), "\n")
#   cat("year NA%:", mean(is.na(data$year)) * 100, "\n")
#   print(summary(data$year))
#   print(sort(unique(data$year))[1:20])
# }
# if ("Year" %in% names(data)) {
#   cat("Year class:", class(data$Year), "\n")
#   cat("Year NA%:", mean(is.na(data$Year)) * 100, "\n")
#   print(summary(data$Year))
# }

# if (!"year" %in% names(data) && "Year" %in% names(data)) {
#   data <- data %>% rename(year = Year)
# }
# if (!"year" %in% names(data)) {
#   data$year <- NA_integer_
# }

# # Basic sanity checks
# needed_cols <- c("lyt_x", "lyt_y", "continent", "country", "Abstract_cleaned")
# missing_cols <- setdiff(needed_cols, names(data))
# if (length(missing_cols) > 0) {
#   stop("Missing required columns in data: ", paste(missing_cols, collapse = ", "))
# }

# # jitter for plotting points
# set.seed(42)
# data <- data %>%
#   mutate(
#     lyt_x_jit = lyt_x + rnorm(n(), sd = .2),
#     lyt_y_jit = lyt_y + rnorm(n(), sd = .2)
#   )

# # ---------------------------
# # Define 5 continents palette etc.
# # ---------------------------
# continents <- tibble(
#   continent = 1:5,
#   order = 1:5,
#   number = 1:5,
#   colors = viridis::mako(5, end = .8)[order]
# ) %>%
#   mutate(
#     colors_white  = memnet::cmix(colors, "white", .5),
#     colors_white2 = memnet::cmix(colors, "white", .75)
#   )

# # ---------------------------
# # Centroids (continent + country)
# # ---------------------------
# continent_centroids <- data %>%
#   group_by(continent) %>%
#   summarise(
#     lyt_x = mean(lyt_x, na.rm = TRUE),
#     lyt_y = mean(lyt_y, na.rm = TRUE),
#     n_papers = n(),
#     .groups = "drop"
#   )

# country_centroids <- data %>%
#   group_by(continent, country) %>%
#   summarise(
#     lyt_x = mean(lyt_x, na.rm = TRUE),
#     lyt_y = mean(lyt_y, na.rm = TRUE),
#     n_papers = n(),
#     .groups = "drop"
#   ) %>%
#   left_join(country_names, by = "country") %>%
#   mutate(
#     country_name = ifelse(is.na(country_name), paste0("Cluster ", country), country_name)
#   )

# # ---------------------------
# # Smart label placement (creates lab_x/lab_y)
# # ---------------------------
# smart_label_positions <- function(df) {
#   df <- df %>% mutate(lab_x = NA_real_, lab_y = NA_real_)
#   df <- df %>% arrange(desc(n_papers))

#   for (i in 1:nrow(df)) {
#     angles <- seq(0, 2*pi, length.out = 8)
#     distances <- seq(0.5, 3, by = 0.5)

#     best_pos <- c(df$lyt_x[i], df$lyt_y[i])
#     best_score <- -Inf

#     for (dist in distances) {
#       for (ang in angles) {
#         tx <- df$lyt_x[i] + dist * cos(ang)
#         ty <- df$lyt_y[i] + dist * sin(ang)

#         if (i > 1) {
#           prev <- df[1:(i-1), ]
#           ok <- !(is.na(prev$lab_x) | is.na(prev$lab_y))
#           if (any(ok)) {
#             d_to_others <- sqrt((tx - prev$lab_x[ok])^2 + (ty - prev$lab_y[ok])^2)
#             min_dist <- min(d_to_others, na.rm = TRUE)
#           } else {
#             min_dist <- Inf
#           }
#         } else {
#           min_dist <- Inf
#         }

#         score <- min_dist - dist * 0.5
#         if (score > best_score) {
#           best_score <- score
#           best_pos <- c(tx, ty)
#         }
#       }
#     }

#     df$lab_x[i] <- best_pos[1]
#     df$lab_y[i] <- best_pos[2]
#   }

#   df
# }

# # ---------------------------
# # Your continent labels (EDIT THESE if you want)
# # ---------------------------
# continent_labels <- continent_centroids %>%
#   smart_label_positions() %>%
#   left_join(continents %>% select(continent, colors, number), by = "continent") %>%
#   mutate(
#     adj = 0.5,  # used by base::text()
#     labels = c(
#       "Social Equity &\nPolicy",
#       "Business Networks &\nMarkets",
#       "Collective Behavior &\nEmergence",
#       "Norm Emergence &\nCoordination",
#       "Transportation &\nEV Adoption"
#     )
#   )

# # Join label positions into continents (for consistent access)
# continents <- continents %>%
#   left_join(continent_labels %>% select(continent, lab_x, lab_y, adj, labels),
#             by = "continent")

# # ---------------------------
# # Plot: map
# # ---------------------------
# out_map <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/1_cluster_map_improved.png"
# png(out_map, width = 10, height = 6, unit = "in", res = 300)

# xlim <- range(data$lyt_x, na.rm = TRUE)
# ylim <- range(data$lyt_y, na.rm = TRUE)

# par(mar = c(0,0,0,0))
# plot.new()
# plot.window(xlim = xlim * c(1.1, 1.1), ylim = ylim * c(1.1, 1.2))

# for (i in 1:nrow(continents)) {

#   data_i <- data %>%
#     filter(continent == i) %>%
#     mutate(
#       lyt_x = lyt_x + runif(n(), -.3, .3),
#       lyt_y = lyt_y + runif(n(), -.3, .3)
#     )

#   if (nrow(data_i) < 3) next

#   hull <- concaveman::concaveman(cbind(data_i$lyt_x, data_i$lyt_y),
#                                  concavity = 2, length_threshold = 2)

#   hull[,1] <- round(round(hull[,1]*2, 1)/2, 2)
#   hull[,2] <- round(round(hull[,2]*2, 1)/2, 2)

#   rx <- range(hull[,1]); ry <- range(hull[,2])

#   grid <- expand.grid(
#     x = seq(rx[1], rx[2], .05) %>% round(2),
#     y = seq(ry[1], ry[2], .05) %>% round(2)
#   ) %>% as.matrix()

#   index <- expand.grid(
#     xi = 1:length(seq(rx[1], rx[2], .05)),
#     yi = 1:length(seq(ry[1], ry[2], .05))
#   ) %>% as.matrix()

#   pts <- matrix(nrow = nrow(grid), ncol = 2, dimnames = list(NULL, c("in","cntry")))
#   for (k in 1:nrow(grid)) {
#     pt <- grid[k,]
#     pts[k,1] <- pnpoly(pt, hull)
#     dists <- sqrt((data_i$lyt_x - pt[1])^2 + (data_i$lyt_y - pt[2])^2)
#     pts[k,2] <- data_i$country[which.min(dists)]
#   }

#   pts <- cbind(index, cbind(grid, pts))
#   pts <- pts[pts[,"in"] > 0, , drop = FALSE]

#   uni_countries <- unique(data_i$country)
#   col_fill <- continents$colors_white2[i]

#   for (j in seq_along(uni_countries)) {
#     pts_cntry <- pts[pts[,"cntry"] == uni_countries[j], c("x","y"), drop = FALSE]
#     if (nrow(pts_cntry) == 0) next

#     border <- rep(0, nrow(pts_cntry))
#     for (k in 1:nrow(pts_cntry)) {
#       pt <- pts_cntry[k,]
#       dists <- (abs(pts_cntry[,"x"] - pt[1]) + abs(pts_cntry[,"y"] - pt[2])) / 2
#       border[k] <- ifelse(sum(round(dists,2) == .05) == 8, 0, 1)
#     }

#     w <- .05
#     rect(pts_cntry[,1] - w/2, pts_cntry[,2] - w/2,
#          pts_cntry[,1] + w/2, pts_cntry[,2] + w/2,
#          col = ifelse(border == 1, "white", col_fill),
#          border = NA)
#   }

#   points(
#     data_i$lyt_x_jit,
#     data_i$lyt_y_jit,
#     bg  = continents$colors[i],
#     col = continents$colors_white[i],
#     pch = 21, cex = .2, lwd = .1
#   )
# }

# # # Country letter labels (only for bigger country clusters)
# # for (cont in 1:5) {
# #   country_subset <- country_centroids %>% filter(continent == cont, n_papers > 10)
# #   if (nrow(country_subset) == 0) next

# #   text(country_subset$lyt_x, country_subset$lyt_y,
# #        labels = country_subset$country_name,
# #        cex = 0.45, col = "gray30", font = 1)
# # }

# # Continent labels + connector lines
# for (i in 1:nrow(continent_labels)) {
#   ci <- continent_labels %>% slice(i)

#   lines(c(ci$lyt_x, ci$lab_x), c(ci$lyt_y, ci$lab_y),
#         col = ci$colors, lwd = 1, lty = 2)

#   # rect(ci$lab_x - strwidth(ci$labels, cex = 0.9)/2 - 0.05,
#   #      ci$lab_y - strheight(ci$labels, cex = 0.9)/2 - 0.02,
#   #      ci$lab_x + strwidth(ci$labels, cex = 0.9)/2 + 0.05,
#   #      ci$lab_y + strheight(ci$labels, cex = 0.9)/2 + 0.02,
#   #      col = "white", border = NA)

#   text(ci$lab_x, ci$lab_y,
#        labels = paste0(ci$labels, "\n(", ci$number, ")"),
#        cex = 0.9,
#        col = ci$colors,
#        font = 2)
# }

# # legend("bottomright",
# #        legend = c("A), B), C)... = country clusters within continent"),
# #        cex = 0.6, bty = "n", text.col = "gray40")

# dev.off()
# cat("Saved map:", out_map, "\n")

# # ---------------------------
# # Export top tags per continent (if tags_clean exists)
# # ---------------------------
# if ("tags_clean" %in% names(data)) {
#   cat("Extracting top tags per continent...\n")

#   get_tags <- function(continent_id) {
#     tt <- data$tags_clean[data$continent == continent_id] %>%
#       unlist() %>%
#       table() %>%
#       sort(decreasing = TRUE) %>%
#       head(50) %>%
#       as.data.frame()

#     out <- cbind(continent = continent_id, tt)
#     names(out)[2:3] <- c("Tag", "Frequency")
#     out
#   }

#   tag_dfs <- lapply(1:5, get_tags) %>% bind_rows()
#   write_csv(tag_dfs, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/continent_tags.csv")
#   cat("Saved continent tags CSV.\n")
# } else {
#   cat("Note: data has no tags_clean column, skipping tag export.\n")
# }

# # ---------------------------
# # Timeline (uses data$year)

# data_rds <- readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.RDS")

# data_csv <- readr::read_csv(
#   "/rds/homes/v/vaw508/projects/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300_YE.csv",
#   show_col_types = FALSE
# )

# cat("RDS cols:\n"); print(names(data_rds))
# cat("CSV cols:\n"); print(names(data_csv))

# # ---------------------------
# candidate_keys <- c(
#   "DOI", "doi",
#   "EID", "eid",
#   "Scopus_ID", "scopus_id", "scopusid",
#   "PaperID", "paper_id", "id",
#   "Title", "title", "Document title", "Document_title"
# )

# common_keys <- intersect(candidate_keys, intersect(names(data_rds), names(data_csv)))
# if (length(common_keys) == 0) {
#   stop(
#     "No obvious join key found between RDS and CSV.\n",
#     "Look for a shared identifier (DOI/EID/title/id) and use it explicitly in left_join().\n",
#     "Example: left_join(data_rds, data_csv %>% select(MYKEY, Year), by = c('MYKEY'='MYKEY'))"
#   )
# }

# join_key <- common_keys[1]
# cat("Using join key:", join_key, "\n")
# )
# year_candidates <- c("Year", "year", "PY", "pub_year", "PublicationYear", "publication_year")
# year_col <- intersect(year_candidates, names(data_csv))
# if (length(year_col) == 0) stop("CSV has no Year-like column. Found none of: ", paste(year_candidates, collapse=", "))
# year_col <- year_col[1]
# cat("Using year column from CSV:", year_col, "\n")

# data <- data_rds %>%
#   left_join(
#     data_csv %>%
#       select(all_of(join_key), Year_raw = all_of(year_col)) %>%
#       distinct(all_of(join_key), .keep_all = TRUE),
#     by = join_key
#   )


# data <- data %>%
#   mutate(
#     Year = readr::parse_number(as.character(Year_raw)),  
#     Year = as.integer(floor(Year))                       # ensures integer year
#   )


# data_year <- data %>%
#   filter(!is.na(Year), Year >= 1900, Year <= 2100)

# cat("Year coverage:\n")
# cat("  total rows:", nrow(data), "\n")
# cat("  rows with valid Year:", nrow(data_year), "\n")
# cat("  example Years:", paste(head(sort(unique(data_year$Year)), 10), collapse=", "), "\n")

# # ---------------------------
# # 5) Plot timeline
# # ---------------------------
# timeline_df <- data_year %>%
#   count(Year, name = "n") %>%
#   arrange(Year)

# p_timeline <- ggplot(timeline_df, aes(x = Year, y = n)) +
#   geom_line(linewidth = 1) +
#   geom_point(size = 2) +
#   theme_minimal() +
#   labs(
#     title = "Growth of ABM Literature",
#     x = "Year",
#     y = "Number of Articles"
#   )

# out_timeline <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/ABM_timeline.png"
# ggsave(out_timeline, p_timeline, width = 10, height = 5, dpi = 300)

# cat("Saved timeline:", out_timeline, "\n")
