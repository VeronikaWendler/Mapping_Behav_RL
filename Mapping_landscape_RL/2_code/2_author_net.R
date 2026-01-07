require(tidyverse)
require(Matrix)
Rcpp::sourceCpp("2_code/_helpers.cpp")

data = read_csv("1_data/data_cleaned_filtered.csv")


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

author_cos = arma_cosine(author_emb);author_cos[is.na(author_cos)] = 0
rownames(author_cos) = colnames(author_cos) = data$Authors

is = which(str_detect(data$Authors, "Wulff D"))
sort(author_cos[is[1],], decreasing = TRUE)[1:10]

is = which(str_detect(data$Authors, "Wulff D"))
sort(author_cos_2[is[1],], decreasing = TRUE)[1:10]

saveRDS(author_emb, "1_data/embs/author_emb.RDS")



