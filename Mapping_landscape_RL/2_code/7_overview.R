require(tidyverse)
require(tidytext)
source("2_code/_textboxes.R")
require(remotes)
Rcpp::sourceCpp("2_code/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

data = readRDS("1_data/data_cleaned_filtered_tagged_clustered.RDS") 

# SIZE ----------

cluster_counts = data %>% 
  group_by(country) %>% 
  summarize(n = n()) %>% 
  pull(n, country)

# TIMELINE ------

lims = range(data$Year)

dens_x = sapply(1:30, function(x){
  dens = density(data$Year[data$country == x], 
                 from = lims[1], to = lims[2], bw = 2)
  dens$x}) |> t()

dens_y = sapply(1:30, function(x){
  dens = density(data$Year[data$country == x], 
                 from = lims[1], to = lims[2], bw = 2)
  dens$y}) |> t()

dens_y_norm = t(t(dens_y) / colSums(dens_y))

# WRITE FOR LABELS ----------

colors = tibble(
  continent = 1:10, 
  order = c(4,9,10,8,6,5,7,3,2,1),
  number = c(1,5,9,2,6,8,10,4,7,3),
  colors = viridis::mako(10, end = .8)[continent[order]],
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .7))

clusters = data %>% 
  left_join(colors |> select(continent, number)) |> 
  group_by(country, number, continent) %>% 
  summarize(m = mean(Year), mm = median(Year), min = min(Year)) %>% 
  ungroup() %>% 
  arrange(number, mm, min) |> 
  group_by(continent, number) |> 
  mutate(code = paste0(number, LETTERS[1:n()])) |> 
  arrange(number, mm, min) 

cluster_ord = clusters %>% pull(country)
continent_ord = clusters %>% pull(continent)
codes = clusters |> pull(code)

# OVERVIEW ----------


png("3_figures/2_cluster_overview.png", width=18, height = 18, unit = "in", res=200)

n_cluster = max(data$country)
cols = viridis::mako(n_cluster, begin = 0, end = .8)
cols_tr = viridis::mako(n_cluster, begin = 0, end = .8, alpha = .5)
cols_coh = viridis::cividis(3, begin = .2, end = .7, alpha=.5)

widths = c(1.6, .65, 2.4, 2.1, 2.1)
heights = c(1, rep(1, 14))

lyt_m_1 = matrix(1:((length(widths)+1)*(n_cluster/2)),nrow=n_cluster/2,byrow = T)
lyt_m_2 = matrix(1:((length(widths))*(n_cluster/2)),nrow=n_cluster/2,byrow = T)
#lyt_m_3 = matrix(1:((length(widths))*(n_cluster/3)),nrow=n_cluster/3,byrow = T)
lyt = cbind(lyt_m_1, lyt_m_2 + (n_cluster/2)*(length(widths)+1))

layout(lyt, widths = c(widths, .2, widths))

par(lheight=.78)
for(i in 1:n_cluster){
  
  cl = cluster_ord[i]
  code = codes[i]
  cont = continent_ord[i]
  col = colors$colors[cont]
  col_tr = colors$colors_white2[cont]
  
  # mini map
  
  par(mar=c(.5,1.5,.5,.5))
  plot.new();plot.window(xlim=range(data$lyt_x),
                         ylim=range(data$lyt_y))
  points(data$lyt_x, data$lyt_y, pch = 16,
         cex = ifelse(data$country == cl, .6, ifelse(data$continent == cont, .3, .2)), 
         col = ifelse(data$country == cl, col, 
                      ifelse(data$continent == cont, col_tr, "grey80")))
  
  # number of articles
  
  par(mar=c(1,.5,1,.5))
  plot.new();plot.window(xlim=c(-1,1),ylim=c(-1,1))
  text(0,.4, label = code, cex=2.4, font = 2)    
  text(0,-.2, label = cluster_counts[as.character(cl)], cex=1.8, font=1)  
  text(0,-.55, label = "articles", cex=1.2)  
  
  # time line
  
  par(mar=c(5,1.5,1,1.5))
  x = dens_x[cl,]
  x = c(lims[1], x, x[length(x)],lims[2])
  y = dens_y[cl, ]
  y = c(0, y, 0, 0)
  plot.new();plot.window(xlim=lims,ylim=c(0,max(dens_y)*1.05))
  polygon(x, y, col = col_tr, border=NA)
  lines(x,y,lwd=2,col=col)
  lines(c(1970,2025),c(0,0))
  mtext(c(seq(1970,2020,20),2025), at = c(seq(1970,2020,20),2025), cex=.8, side=1, line=.2)
  if(i %in% c(1, 16)) mtext("Year", side=1,line=2.5, font=2, cex=1.2)
  
  # word cloud
  
  tab = data |> 
    filter(country == cl) |> 
    select(tags_clean) |> 
    unlist() |> 
    table() |> 
    sort(decreasing = T)
  tab = tab[!names(tab) %in% c("Reinforcement Learning", "Neuroscience", "Decision Making")]
  tab = tab[1:min(8, length(tab))]
  
  par(mar=c(1,0,1,0))

  text_box(names(tab), sqrt(c(tab)), base_cex=1.1, text_align = "left", 
             separator_padding = .03, top_whitespace = .1, square_size = c(0, 2.3, 0, 1),
             line_spacing_factor = .1)
  if(i %in% c(1, 16)) mtext("Tags",side=3, cex=1.2, font=2, line=-.7, adj = 0, at = 0)
  
  journal = data %>% filter(country == cl) %>% count(`Source title`) |> arrange(desc(n)) |> slice(1:6)

  par(mar=c(1,0,1,0))
  
  text_box(journal$`Source title`, sqrt(journal$n), base_cex=.9, text_align = "left", 
               separator_padding = .03, top_whitespace = .1, square_size = c(0, 2.3, 0, 1),
               line_spacing_factor = .1)
  
  if(i %in% c(1, 16)) mtext("Journals",side=3, cex=1.2, font=2, line=-.7, adj = 0, at = 0)
    
  if(i <= 15) plot.new();plot.window(c(0,0),c(0,0))
  
}

dev.off()



