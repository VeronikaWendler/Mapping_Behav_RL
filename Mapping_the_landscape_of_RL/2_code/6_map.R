require(tidyverse)
require(remotes)
Rcpp::sourceCpp("2_code/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

data = readRDS("1_data/data_cleaned_filtered_tagged_clustered.RDS")

set.seed(42)
data = data |> mutate(lyt_x_jit = lyt_x + rnorm(n(), sd = .2), lyt_y_jit = lyt_y + rnorm(n(), sd = .2))

png("3_figures/1_cluster_map.png",
    width = 8, height = 4.8, unit = "in", res = 300)

continents = tibble(
  continent = 1:10, 
  order = c(4,9,10,8,6,5,7,3,2,1),
  number = c(1,5,9,2,6,8,10,4,7,3),
  colors = viridis::mako(10, end = .8)[continent[order]],
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .75))

centroids = data %>% 
  group_by(continent) %>% 
  summarize(lyt_x = mean(lyt_x),
            lyt_y = mean(lyt_y)) %>% 
  mutate(lab_x = lyt_x + c(-3,0,0,-5,3,3,-1,-2,-1,-2)*1.5,
         lab_y = lyt_y + c(7,6,3,0,-8,-1,1,11,4,0)*1.5, 
         adj = c(.5, .5, .5, 1, .5, 0, 1, .5, .5, 1))

# continents = continents %>% left_join(centroids) %>% 
#   mutate(labels = c("Probabilistic\nLearning","Neural Reward\nMechanisms",
#                     "Visual Attention I","Behavioral\nDecision\nMaking",
#                     "Computational\nPsychiatry","Error Signals",
#                     "Visual Attention II","Decision\nNeuroscience",
#                     "Schizophrenia","Intertemporal\nChoice"))

continents = continents %>% left_join(centroids) %>% 
  mutate(labels = c("Learning\nMechanisms","Neural Reward\nMechanisms",
                    "Attentional Capture","Behavioral\nDecision\nMaking",
                    "Computational\nPsychiatry","Feedback\nProcessing",
                    "Visual Search","Decision\nNeuroscience",
                    "Schizophrenia","Temporal\nDynamics"))


xlim = range(data$lyt_x) ; ylim = range(data$lyt_y)
par(mar=c(0,0,0,0))
plot.new();plot.window(xlim = xlim * c(1.1, 1.1), ylim = ylim * c(1, 1.2))

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
       labels = paste0(continents_i$labels," (",continents_i$number, ")"), cex=1, adj = continents_i$adj,
       col = continents_i$colors, font = 1)
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



