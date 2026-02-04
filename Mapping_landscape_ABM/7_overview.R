# 7_overview_ABM.R
require(tidyverse)
require(tidytext)
source("2_code/_textboxes.R")
require(remotes)
Rcpp::sourceCpp("2_code/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

# Load YOUR data with objective continents
data = readRDS("Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.RDS") 

# YOUR CONTINENT COLORS (5 continents)
colors = tibble(
  continent = 1:5, 
  order = c(1,2,3,4,5),
  number = c(1,2,3,4,5),
  colors = viridis::mako(5, end = .8)[order],
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .7))

# SIZE ----------
cluster_counts = data %>% 
  group_by(country) %>% 
  summarize(n = n()) %>% 
  pull(n, country)

# TIMELINE ------
lims = range(data$Year, na.rm = TRUE)

# Create density plots for each cluster
n_clusters = length(unique(data$country))
dens_x = sapply(1:n_clusters, function(x){
  dens = density(data$Year[data$country == x], 
                 from = lims[1], to = lims[2], bw = 2, na.rm = TRUE)
  dens$x}) |> t()

dens_y = sapply(1:n_clusters, function(x){
  dens = density(data$Year[data$country == x], 
                 from = lims[1], to = lims[2], bw = 2, na.rm = TRUE)
  dens$y}) |> t()

# WRITE FOR LABELS ----------
clusters = data %>% 
  left_join(colors |> select(continent, number)) |> 
  group_by(country, number, continent) %>% 
  summarize(m = mean(Year, na.rm = TRUE), 
           mm = median(Year, na.rm = TRUE), 
           min = min(Year, na.rm = TRUE)) %>% 
  ungroup() %>% 
  arrange(number, mm, min) |> 
  group_by(continent, number) |> 
  mutate(code = paste0(number, LETTERS[1:n()])) |> 
  arrange(number, mm, min) 

cluster_ord = clusters %>% pull(country)
continent_ord = clusters %>% pull(continent)
codes = clusters |> pull(code)

# OVERVIEW ----------
png("3_figures/ABM_cluster_overview.png", 
    width = 14, height = 20, unit = "in", res = 200)

# Layout for 30 clusters (15 per column)
n_cluster = length(cluster_ord)
cols = viridis::mako(n_cluster, begin = 0, end = .8)
cols_tr = viridis::mako(n_cluster, begin = 0, end = .8, alpha = .5)

# Panel widths: mini-map, count, timeline, tags, journals
widths = c(1.5, 0.7, 2.0, 2.0, 2.0)

# Create layout - 15 clusters per column
first_col = 1:15
second_col = 16:n_cluster

layout_mat = matrix(0, nrow = max(length(first_col), length(second_col)), 
                    ncol = length(widths) * 2 + 1)

# Fill first column
for(i in seq_along(first_col)) {
  start_idx = (i-1)*length(widths) + 1
  layout_mat[i, 1:length(widths)] = start_idx:(start_idx + length(widths) - 1)
}

# Fill second column  
for(i in seq_along(second_col)) {
  start_idx = max(layout_mat, na.rm = TRUE) + 1
  layout_mat[i, (length(widths)+2):(2*length(widths)+1)] = 
    start_idx:(start_idx + length(widths) - 1)
}

layout(layout_mat, widths = c(widths, 0.2, widths))

par(lheight = 0.78, family = "sans")

for(i in 1:n_cluster){
  
  cl = cluster_ord[i]
  code = codes[i]
  cont = continent_ord[i]
  col = colors$colors[cont]
  col_tr = colors$colors_white2[cont]
  
  # 1. MINI-MAP -----
  par(mar = c(0.5, 1.5, 0.5, 0.5))
  plot.new()
  plot.window(xlim = range(data$lyt_x, na.rm = TRUE),
              ylim = range(data$lyt_y, na.rm = TRUE))
  # Background points
  points(data$lyt_x, data$lyt_y, pch = 16, cex = 0.15, col = "grey90")
  # Same continent points
  same_cont = data$country != cl & data$continent == cont
  points(data$lyt_x[same_cont], data$lyt_y[same_cont], 
         pch = 16, cex = 0.25, col = col_tr)
  # Current cluster points
  current = data$country == cl
  points(data$lyt_x[current], data$lyt_y[current], 
         pch = 16, cex = 0.6, col = col)
  
  # 2. CLUSTER SIZE -----
  par(mar = c(1, 0.5, 1, 0.5))
  plot.new()
  plot.window(xlim = c(-1, 1), ylim = c(-1, 1))
  text(0, 0.4, label = code, cex = 2.4, font = 2, col = col)    
  text(0, -0.2, label = cluster_counts[as.character(cl)], 
       cex = 1.8, font = 1)  
  text(0, -0.55, label = "articles", cex = 1.2)  
  
  # 3. TIMELINE -----
  par(mar = c(5, 1.5, 1, 1.5))
  x = dens_x[cl, ]
  x = c(lims[1], x, x[length(x)], lims[2])
  y = dens_y[cl, ]
  y = c(0, y, 0, 0)
  plot.new()
  plot.window(xlim = lims, ylim = c(0, max(dens_y, na.rm = TRUE) * 1.05))
  polygon(x, y, col = col_tr, border = NA)
  lines(x, y, lwd = 2, col = col)
  lines(c(lims[1], lims[2]), c(0, 0))
  
  # X-axis labels
  year_breaks = seq(floor(lims[1]/10)*10, ceiling(lims[2]/10)*10, by = 10)
  axis(1, at = year_breaks, labels = year_breaks, cex.axis = 0.8, padj = -0.5)
  
  if(i %in% c(1, 16)) {
    mtext("Year", side = 1, line = 2.5, font = 2, cex = 1.2)
  }
  
  # 4. TOP TAGS -----
  par(mar = c(1, 0, 1, 0))
  
  # Get top tags for this cluster
  tab = data |> 
    filter(country == cl) |> 
    select(tags_clean) |> 
    unlist() |> 
    table() |> 
    sort(decreasing = TRUE)
  
  # Filter out generic ABM terms if you want
  generic_terms = c("Agent-Based Modeling", "Agent-based model", "ABM", 
                   "Simulation", "Modeling")
  tab = tab[!names(tab) %in% generic_terms]
  
  # Take top 6-8 tags
  tab = tab[1:min(8, length(tab))]
  
  if(length(tab) > 0) {
    text_box(names(tab), sqrt(c(tab)), base_cex = 1.0, 
             text_align = "left", separator_padding = 0.03, 
             top_whitespace = 0.1, square_size = c(0, 2.3, 0, 1),
             line_spacing_factor = 0.1)
  } else {
    plot.new()
    plot.window(c(0, 1), c(0, 1))
    text(0.5, 0.5, "No tags", cex = 0.9, col = "gray50")
  }
  
  if(i %in% c(1, 16)) {
    mtext("Key Topics", side = 3, cex = 1.2, font = 2, line = -0.7, 
          adj = 0, at = 0)
  }
  
  # 5. TOP JOURNALS -----
  par(mar = c(1, 0, 1, 0))
  
  journal = data %>% 
    filter(country == cl) %>% 
    count(`Source title`) |> 
    arrange(desc(n)) |> 
    slice(1:6)
  
  if(nrow(journal) > 0) {
    text_box(journal$`Source title`, sqrt(journal$n), base_cex = 0.85, 
             text_align = "left", separator_padding = 0.03, 
             top_whitespace = 0.1, square_size = c(0, 2.3, 0, 1),
             line_spacing_factor = 0.1)
  } else {
    plot.new()
    plot.window(c(0, 1), c(0, 1))
    text(0.5, 0.5, "No journal data", cex = 0.9, col = "gray50")
  }
  
  if(i %in% c(1, 16)) {
    mtext("Top Journals", side = 3, cex = 1.2, font = 2, line = -0.7, 
          adj = 0, at = 0)
  }
  
  # Add separator between columns if needed
  if(i == 15) {
    par(mar = c(0, 0, 0, 0))
    plot.new()
    plot.window(c(0, 1), c(0, 1))
  }
}

dev.off()

cat("Cluster overview saved to: 3_figures/ABM_cluster_overview.png\n")

