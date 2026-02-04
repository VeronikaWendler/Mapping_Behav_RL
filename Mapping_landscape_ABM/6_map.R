require(tidyverse)
require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")
if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)


data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.RDS")

set.seed(42)
data = data |> mutate(lyt_x_jit = lyt_x + rnorm(n(), sd = .2), lyt_y_jit = lyt_y + rnorm(n(), sd = .2))

png("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/1_cluster_map.png",
    width = 8, height = 4.8, unit = "in", res = 300)

continents = tibble(
  continent = 1:5, 
  order = c(1,2,3,4,5),
  number = c(1,2,3,4,5),
  colors = viridis::mako(5, end = .8)[order],  # 5 colors
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .75))

centroids = data %>% 
  group_by(continent) %>% 
  summarize(lyt_x = mean(lyt_x),
            lyt_y = mean(lyt_y)) %>% 
  mutate(lab_x = lyt_x + c(-2, 2, -2, 2, 0)*1.5,
         lab_y = lyt_y + c(2, 2, -2, -2, 3)*1.5, 
         adj = c(1, 0, 1, 0, .5))  # Adjust label alignment

# YOUR LABELS BASED ON FINDINGS
continents = continents %>% left_join(centroids) %>% 
  mutate(labels = c(
    "Social Equity &\nPolicy Modeling",         # Region 1 (1545 papers)
    "Business Networks &\nMarket Dynamics",     # Region 4 (1495 papers)  
    "Collective Behavior &\nEmergent Systems",  # Region 3 (1456 papers)
    "Norm Emergence &\nSocial Coordination",    # Region 2 (1353 papers)
    "Transportation &\nEV Adoption"             # Region 5 (945 papers)
  ))

xlim = range(data$lyt_x) ; ylim = range(data$lyt_y)
par(mar=c(0,0,0,0))
plot.new();plot.window(xlim = xlim * c(1.1, 1.1), ylim = ylim * c(1, 1.2))

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


for(i in 1:nrow(continents)){
   continents_i = continents %>% slice(i)
   text(continents_i$lab_x, continents_i$lab_y, 
       labels = paste0(continents_i$labels,"\n(",continents_i$number, ")"), 
       cex = 1.2, adj = continents_i$adj,
       col = continents_i$colors, font = 2)  # Bold font
}



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
  count(Year) |> 
  mutate(n_exp = ifelse(Year == 2025, n * (12/5), n)) |> 
  ggplot(aes(x = Year, y = n)) +
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

for(keyword in keywords_to_check) {
  plot <- data |> 
    mutate(hit = str_detect(tolower(Abstract_cleaned), keyword)) |> 
    ggplot(aes(x = lyt_x, y = lyt_y)) + 
    geom_point(data = . %>% filter(!hit), color = "gray90", alpha = 0.2, size = 0.5) +
    geom_point(data = . %>% filter(hit), aes(color = factor(continent)), 
               alpha = 0.8, size = 1) +
    scale_color_viridis_d(end = 0.8) +
    theme_void() +
    labs(title = paste("Papers containing:", keyword),
         subtitle = paste(sum(data$hit), "papers")) +
    theme(legend.position = "none",
          plot.title = element_text(hjust = 0.5, face = "bold"))
  
  ggsave(paste0("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/keyword_", gsub("-", "_", keyword), ".png"), 
         plot, width = 8, height = 6, dpi = 300)
}
