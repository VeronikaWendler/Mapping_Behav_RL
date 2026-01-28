require(tidyverse)
require(Matrix)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

data = read_csv("Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300.csv")

process = function(x) {
  x %>% str_to_lower() %>% 
    str_replace_all("[:punct:]"," ") %>% 
    str_replace_all("[:digit:]"," ") %>% 
    str_replace_all("\\b[:alpha:]{1,3}\\b"," ") %>% 
    str_squish()
}

references_split = str_split(data$References, "; ")
references_split_processed = lapply(references_split, process)

reference_uni = unlist(references_split_processed) |> unique()

ref_cooc = Matrix(0, nrow = nrow(data), ncol = length(reference_uni),
                  dimnames = list(1:nrow(data), reference_uni),
                  sparse = TRUE)

for(i in 1:length(references_split_processed)){
  refs = references_split_processed[[i]]
  ref_cooc[i,refs] = ref_cooc[i,refs] + 1
}

sel = which(colSums(ref_cooc) > 4) |> unname()
ref_cooc_sel = ref_cooc[,sel]

ref_ppmi = ppmi_sparse(ref_cooc_sel)
ref_svd = sparsesvd::sparsesvd(ref_ppmi, 384)
ref_emb = ref_svd$u %*% diag(ref_svd$d)
rownames(ref_emb) = data$id

ref_cos = arma_cosine(ref_emb)
rownames(ref_cos) = colnames(ref_cos) = data$Title

# check: pick any paper row and show nearest neighbours (reference-based)
set.seed(100)
i = sample(1:nrow(data), 1)
sort(ref_cos[i,], decreasing = TRUE)[1:5]

saveRDS(ref_emb, "Mapping_landscape_ABM/Data/embs_300/references_emb.RDS")
