require(tidyverse)
require(reticulate)
use_condaenv("form")
source("2_code/_cubes.R")


data = readRDS("1_data/data_cleaned_filtered_tagged_clustered.RDS")
emb = readRDS("1_data/embs/combined_emb.RDS")

author_net = arma_cosine(emb[,1:384]); author_net[is.na(author_net)] = 0
reference_net = arma_cosine(emb[,(1:384) + 384]); reference_net[is.na(reference_net)] = 0
semantic_net = arma_cosine(emb[,(1:384) + 384*2])

rownames(author_net) = rownames(reference_net) = rownames(semantic_net) = 
  data$title_id
colnames(author_net) = colnames(reference_net) = colnames(semantic_net) = 
  data$title_id


model = pacmap$PaCMAP(n_components=as.integer(3), n_neighbors=as.integer(100), 
                      MN_ratio=2, FP_ratio=20.0, distance="angular")

get_cube = function(emb, col){
  
  clusters = model$fit_transform(emb)
  
  to01 = function(x, f = 10) (x - min(x))/(max(x) - min(x)) * f
  clusters = apply(clusters, 2, to01)
  
  angles = c(30, 36.8, 23)
  d = 50
  size = 10
  sq = (square(angles, d = d, size = size) |> apply(2, to01, f = 12) |> t() + c(1.5,-1,0)) |> t()
  
  plot.new();plot.window(xlim=c(.15, 1.35) * 10, ylim=c(-.1, 1.1) * 10)
  segs(sq)
  
  cubes = apply(clusters, 1, function(x){
    list(square(angles, d = d, size = .25, orig = x[c(1,2,3)], scale = TRUE))
  }) |> lapply(function(x) x[[1]])
  
  pos = sapply(cubes, function(x) max(x[,3]))
  clusters = clusters[order(pos),]
  cubes = cubes[order(pos)]
  
  set.seed(42)
  cubes = cubes[sample(length(cubes), 1000)]
  
  for(i in 1:length(cubes)) {
    faces(cubes[[i]], col = col, border = "white")
  }

  segs(sq,2)
  }


png("3_figures/illustration/author.png", width = 8, height = 8, res = 300, unit = "in", bg = "transparent")
get_cube(emb[,(1:384) + 384 * 0], viridis::mako(1, begin = .7, alpha = .7))
dev.off()

png("3_figures/illustration/reference.png", width = 8, height = 8, res = 300, unit = "in", bg = "transparent")
get_cube(emb[,(1:384) + 384 * 1], viridis::mako(1, begin = .5, alpha = .7))
dev.off()

png("3_figures/illustration/semantic.png", width = 8, height = 8, res = 300, unit = "in", bg = "transparent")
get_cube(emb[,(1:384) + 384 * 2], viridis::mako(1, begin = .3, alpha = .7))
dev.off()

png("3_figures/illustration/map.png",width=8, height=8, res = 300, unit = "in", bg = "transparent")
data |> 
  ggplot(aes(x = lyt_x + rnorm(nrow(data), sd = .3), y = lyt_y + rnorm(nrow(data), sd = .3))) + 
  geom_point(pch=21, bg = "black", col = "white", cex = 1.5, stroke = .5) + 
  theme_void()
dev.off()







