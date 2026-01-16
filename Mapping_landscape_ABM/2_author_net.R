require(tidyverse)
require(Matrix)
Rcpp::sourceCpp("_helpers.cpp")

data = read_csv("Data/data_cleaned_filtered_4_200.csv")

author_split = str_split(data$`Author(s) ID` %>% 
                           str_remove_all("[:blank:]"), ";")
name_split = str_split(data$Authors, ";")

author_tab = tibble(id = unlist(author_split), 
                    name = unlist(name_split) %>% str_squish()) %>% 
  group_by(id) |> 
  summarize(name = first(name), 
            n = n())

author_cooc = Matrix(0, 
                     nrow = nrow(data), ncol = nrow(author_tab), 
                     dimnames = list(data$id, author_tab$id), 
                     sparse = TRUE)

for(i in 1:length(author_split)){
  ids = author_split[[i]]
  author_cooc[i,ids] = author_cooc[i,ids] + 1
}

sel = which(colSums(author_cooc) > 1) |> unname()
author_cooc_sel = author_cooc[,sel]

author_ppmi = ppmi_sparse(author_cooc_sel)
author_svd = sparsesvd::sparsesvd(author_ppmi, 384)
author_emb = author_svd$u %*% diag(author_svd$d)
rownames(author_emb) = data$id

author_cos = arma_cosine(author_emb); author_cos[is.na(author_cos)] = 0
rownames(author_cos) = colnames(author_cos) = data$Authors

# check, instead of looking at Dirk Wulff, pick any paper row and show nearest neighbours
set.seed(100)
i = sample(1:nrow(data), 1)
sort(author_cos[i,], decreasing = TRUE)[1:10]

out_path <- "Data/embs/author_emb.RDS"
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(author_emb, out_path)