require(tidyverse)
require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")
if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)


data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.RDS")


if ("year" %in% colnames(data) && !"Year" %in% colnames(data)) {
  data <- data %>% rename(Year = year)
  cat("Renamed 'year' to 'Year'\n")
} else if (!"Year" %in% colnames(data)) {
  cat("Warning: No Year/year column found. Creating placeholder...\n")
  data$Year <- NA_real_
}


set.seed(42)
data = data |> mutate(lyt_x_jit = lyt_x + rnorm(n(), sd = .2), lyt_y_jit = lyt_y + rnorm(n(), sd = .2))

png("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/1_cluster_map_improved.png",
    width = 10, height = 6, unit = "in", res = 300)  # Slightly larger

# 5 CONTINENTS
continents = tibble(
  continent = 1:5, 
  order = c(1,2,3,4,5),
  number = c(1,2,3,4,5),
  colors = viridis::mako(5, end = .8)[order],
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .75))

continent_centroids = data %>% 
  group_by(continent) %>% 
  summarize(
    lyt_x = mean(lyt_x),
    lyt_y = mean(lyt_y),
    .groups = "drop"
  )

country_centroids = data %>% 
  group_by(country, continent) %>% 
  summarize(
    lyt_x = mean(lyt_x),
    lyt_y = mean(lyt_y),
    n_papers = n(),
    .groups = "drop"
  ) %>% 
  arrange(continent, desc(n_papers)) %>% 
  group_by(continent) %>% 
  mutate(
    country_label = paste0(LETTERS[1:n()], ")"),  # A), B), C), etc.
    country_num = 1:n()
  )

# SMART LABEL PLACEMENT - Avoid overlaps
smart_label_positions <- function(centroids) {
  positions <- centroids
  placed <- logical(nrow(positions))
  
  # Start with largest clusters first
  positions <- positions %>% arrange(desc(n_papers))
  
  for(i in 1:nrow(positions)) {
    if(!placed[i]) {
      # Try different positions around centroid
      angles <- seq(0, 2*pi, length.out = 8)
      distances <- seq(0.5, 3, by = 0.5)
      
      best_pos <- NULL
      best_score <- -Inf
      
      for(dist in distances) {
        for(angle in angles) {
          test_x <- positions$lyt_x[i] + dist * cos(angle)
          test_y <- positions$lyt_y[i] + dist * sin(angle)
          
          # Check distance to other labels
          if(i > 1) {
            dist_to_others <- sqrt((test_x - positions$lyt_x[1:(i-1)])^2 + 
                                   (test_y - positions$lyt_y[1:(i-1)])^2)
            min_dist <- min(dist_to_others, na.rm = TRUE)
          } else {
            min_dist <- Inf
          }
          
          # Score: far from others but close to own centroid
          score <- min_dist - dist*0.5
          
          if(score > best_score) {
            best_score <- score
            best_pos <- c(test_x, test_y)
          }
        }
      }
      
      positions$lab_x[i] <- best_pos[1]
      positions$lab_y[i] <- best_pos[2]
      placed[i] <- TRUE
    }
  }
  
  return(positions)
}

# Apply smart placement to continents
continent_labels <- continent_centroids %>% 
  left_join(data %>% group_by(continent) %>% summarise(n_papers = n()), by = "continent") %>%
  smart_label_positions() %>%
  left_join(continents %>% select(continent, colors, number), by = "continent") %>%
  mutate(
    labels = c(
      "Social Equity &\nPolicy",         # Smaller
      "Business Networks &\nMarkets",    # Smaller  
      "Collective Behavior &\nEmergence",# Smaller
      "Norm Emergence &\nCoordination",  # Smaller
      "Transportation &\nEV Adoption"    # Smaller
    )
  )

continents <- continents %>%
  left_join(
    continent_labels %>% select(continent, lab_x, lab_y, adj = adj, labels),
    by = "continent"
  )

continent_labels <- continent_labels %>% mutate(adj = 0.5)

# PLOT
xlim = range(data$lyt_x) 
ylim = range(data$lyt_y)
par(mar=c(0,0,0,0))
plot.new()
plot.window(xlim = xlim * c(1.1, 1.1), ylim = ylim * c(1.1, 1.2))

# Loop through YOUR 5 continents
for(i in 1:nrow(continents)){
  
  data_i = data %>% 
    filter(continent == i) %>% 
    mutate(lyt_x = lyt_x + runif(n(), -.3, .3),
           lyt_y = lyt_y + runif(n(), -.3, .3))
  
  hull = concaveman::concaveman(cbind(data_i$lyt_x, data_i$lyt_y), concavity = 2,
                                length_threshold = 2)
  hull[,1] = round(round(hull[,1]*2, 1)/2, 2)
  hull[,2] = round(round(hull[,2]*2, 1)/2, 2)

  rx = range(hull[,1])
  ry = range(hull[,2])
  grid = expand.grid(x = seq(rx[1],rx[2],.05) %>% round(2),
                     y = seq(ry[1],ry[2],.05) %>% round(2)) %>%
    as.matrix()
  index = expand.grid(xi = 1:length(seq(rx[1],rx[2],.05)),
                      yi = 1:length(seq(ry[1],ry[2],.05))) %>%
    as.matrix()
  points = matrix(nrow = nrow(grid), ncol = 2, dimnames=list(NULL, c("in","cntry")))
  for(k in 1:nrow(grid)){
    pt = grid[k,]
    points[k,1] = pnpoly(pt, hull)
    dists = sqrt((data_i$lyt_x - pt[1])**2 + (data_i$lyt_y - pt[2])**2)
    points[k,2] = data_i$country[which.min(dists)]
  }
  points = cbind(index, cbind(grid, points))
  points = points[points[,"in"] > 0,]

  uni_countries = unique(data_i$country)
  col = continents$colors_white2[data_i$continent[1]]

  for(j in 1:length(uni_countries)){
    points_cntry = points[points[,"cntry"] == uni_countries[j],c("x", "y")]

    border = sums = c()
    for(k in 1:nrow(points_cntry)){
      pt = points_cntry[k,c("x","y")]
      dists = (abs(points_cntry[,"x"] - pt[1]) + abs(points_cntry[,"y"] - pt[2])) / 2
      border[k] = ifelse(sum(round(dists,2) == .05) == 8, 0, 1)
    }

    w = .05
    rect(points_cntry[,1] - w/2, points_cntry[,2] - w/2,
         points_cntry[,1] + w/2, points_cntry[,2] + w/2,
         col = ifelse(border, "white", col),
         #col = ifelse(border, "black", NA),
         border = NA)
  }
  
  points(data_i$lyt_x_jit,
         data_i$lyt_y_jit,
         bg = continents$colors[data_i$continent],
         col = continents$colors_white[data_i$continent],
         pch = 21, cex=.2, lwd=.1)
  
  #text(mean(data_i$lyt_x), mean(data_i$lyt_y), label = i, font= 2, cex=2)
}

for(cont in 1:5) {
  country_subset <- country_centroids %>% filter(continent == cont)
  
  # Only label countries with reasonable size
  country_subset <- country_subset %>% filter(n_papers > 10)
  
  if(nrow(country_subset) > 0) {
    # Small gray labels for countries
    text(country_subset$lyt_x, country_subset$lyt_y,
         labels = country_subset$country_label,
         cex = 0.5, col = "gray40", font = 1)
    
    # Optional: tiny connecting line to label
    for(j in 1:nrow(country_subset)) {
      lines(c(country_subset$lyt_x[j], country_subset$lyt_x[j] + 0.1),
            c(country_subset$lyt_y[j], country_subset$lyt_y[j] + 0.1),
            col = "gray80", lwd = 0.5)
    }
  }
}


for(i in 1:nrow(continent_labels)) {
  continent_i <- continent_labels %>% slice(i)
  
  # Draw connecting line from centroid to label
  lines(c(continent_i$lyt_x, continent_i$lab_x),
        c(continent_i$lyt_y, continent_i$lab_y),
        col = continent_i$colors, lwd = 1, lty = 2)
  
  # Label with colored background (better readability)
  rect(continent_i$lab_x - strwidth(continent_i$labels, cex = 0.9)/2 - 0.05,
       continent_i$lab_y - strheight(continent_i$labels, cex = 0.9)/2 - 0.02,
       continent_i$lab_x + strwidth(continent_i$labels, cex = 0.9)/2 + 0.05,
       continent_i$lab_y + strheight(continent_i$labels, cex = 0.9)/2 + 0.02,
       col = "white", border = NA)
  
  # Smaller font for labels
  text(continent_i$lab_x, continent_i$lab_y,
       labels = paste0(continent_i$labels, "\n(", continent_i$number, ")"),
       cex = 0.9,  # SMALLER!
       col = continent_i$colors,
       font = 2)
}



legend("bottomright",
       legend = c("A), B), C)... = Country clusters within continent"),
       cex = 0.6,
       bty = "n",
       text.col = "gray40")

# get_tags = function(x) (data$tags_clean[data$continent == x] |> unlist() |> table() |> sort(decreasing = T))[1:50] |> as.data.frame() |> cbind(continent = x) 
# tag_dfs = lapply(1:10, function(x) get_tags(x)) |> do.call(what = bind_rows)
# names(tag_dfs)[1] = c("Tag")
# write_csv(tag_dfs, "~/Downloads/tags.csv")

dev.off()


# ggplot(continents, aes(x = lyt_x, y = lyt_y, label = number)) + 
#   geom_text()
# 
# 
# d = data |> 
#   mutate(hit = str_detect(Abstract_cleaned, "uncertainty")) 
# d |> 
#   ggplot(aes(x = lyt_x, y = lyt_y)) + 
#   geom_point(data = d |> filter(continent != 9), col = "black") +
#   geom_point(data = d |> filter(continent == 9), fill = "red", pch = 21, col = "white", size=4) +
#   theme_minimal()
# 
# 
# timeline = data |> 
#   count(Year) |> 
#   mutate(n_exp = ifelse(Year == 2025, n * (12/5), n)) |> 
#   ggplot(aes(x = Year, y = n)) +
#   geom_line(aes(x = Year, y = n_exp), col = "deeppink2",linewidth = .8) +
#   geom_line(linewidth = .8) + 
#   geom_point(aes(x = Year, y = n_exp), col = "deeppink2", size = 2) +
#   geom_point(size = 2) + 
#   ylim(c(0, 500)) + 
#   theme_minimal() + 
#   labs(y = "Number of articles") + 
#   scale_x_continuous(breaks = c(seq(1970, 2020, 10), 2025), limits = c(1970, 2030)) +
#   annotate("text", x = 2026, y = 160, label = "Until\nMarch\n2025", hjust = 0) +
#   annotate("text", x = 2026, y = 400, label = "Expected", hjust = 0, col = "deeppink2") 
# 
# ggsave("3_figures/S_timeline.png", timeline, "png", dpi = 300, width = 8, height = 3.8)


cat("Extracting top tags per continent...\n")
get_tags <- function(continent_id) {
  tags <- data$tags_clean[data$continent == continent_id] |> 
    unlist() |> 
    table() |> 
    sort(decreasing = TRUE) |> 
    head(50) |> 
    as.data.frame()
  cbind(continent = continent_id, tags)
}

tag_dfs <- lapply(1:5, get_tags) |> bind_rows()
names(tag_dfs)[2:3] <- c("Tag", "Frequency")
write_csv(tag_dfs, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/continent_tags.csv")
cat("Saved: /rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/continent_tags.csv\n")

cat("Creating publication timeline...\n")
timeline <- data |> 
  count(year) |> 
  mutate(n_exp = ifelse(year == 2025, n * (12/5), n)) |> 
  ggplot(aes(x = year, y = n)) +
  geom_line(aes(y = n_exp), col = "#0072B2", linewidth = 1) +
  geom_line(linewidth = 1) + 
  geom_point(aes(y = n_exp), col = "#0072B2", size = 2.5) +
  geom_point(size = 2.5) + 
  theme_minimal() +
  labs(
    title = "Growth of Agent-Based Modeling Literature",
    y = "Number of Articles",
    caption = "Blue: Expected annual total if current rate continues"
  ) +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold"),
    panel.grid.minor = element_blank()
  )

ggsave("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/ABM_timeline.png", timeline, width = 10, height = 5, dpi = 300)
cat("Saved: /rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/ABM_timeline.png\n")

cat("Creating keyword highlight plots...\n")
keywords_to_check <- c("agent-based", "emergence", "complexity", "simulation", "network")

for (keyword in keywords_to_check) {

  d_kw <- data |>
    mutate(
      hit = str_detect(
        tolower(replace_na(Abstract_cleaned, "")),
        fixed(tolower(keyword))   # fixed() avoids regex issues with "-" etc.
      )
    )

  n_hit <- sum(d_kw$hit, na.rm = TRUE)

  p <- ggplot(d_kw, aes(x = lyt_x, y = lyt_y)) +
    geom_point(data = d_kw |> filter(!hit), color = "gray90", alpha = 0.2, size = 0.5) +
    geom_point(data = d_kw |> filter(hit), aes(color = factor(continent)),
               alpha = 0.8, size = 1) +
    scale_color_viridis_d(end = 0.8) +
    theme_void() +
    labs(
      title = paste("Papers containing:", keyword),
      subtitle = paste(n_hit, "papers")
    ) +
    theme(legend.position = "none")

  ggsave(
    filename = paste0(
      "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/keyword_",
      gsub("[^a-zA-Z0-9]+", "_", keyword),
      ".png"
    ),
    plot = p,
    width = 8, height = 6, dpi = 300
  )
}

