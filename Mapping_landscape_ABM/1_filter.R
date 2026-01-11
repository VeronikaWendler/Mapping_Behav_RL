require(tidyverse)
require(reticulate)
require(glmnet)
use_condaenv("conda_env", required = TRUE)


sbert = import("sentence_transformers")
model = sbert$SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")

# ---

labels = read_tsv("Mapping_landscape_ABM/Data/data_selected_labels_2.csv")

emb = model$encode(labels$abstract)

z = function(x) (x - mean(x))/sd(x)
for(i in 1:ncol(emb)) emb[,i] = z(emb[,i])


nrun = 100
lambdas = exp(seq(-10, 10, 1))
res = array(dim = c(nrun, length(lambdas), 2))
set.seed(42)
for(i in 1:nrun){
  print(i)
  for(j in 1:length(lambdas)){
    sel = sample(nrow(labels), round(nrow(labels)*.8))
    m = glmnet(emb[sel,], labels$out_of_scope[sel], family = "binomial", alpha = 0, lambda = lambdas[j])
    pred = predict(m, newx = emb[-sel,], type = "class") |> as.integer()
    res[i, j, 1] = mean(pred == labels$out_of_scope[-sel])
    pred = predict(m, newx = emb[-sel,], type = "response")
    res[i, j, 2] = -2*sum(log(pred) * labels$out_of_scope[-sel] + log(1-pred) * (1-labels$out_of_scope[-sel]))
    }
  }

colMeans(res[,,1]) |> plot()
colMeans(res[,,2]) |> plot()

# RERUN ----

best_lambda = lambdas[which.min(colMeans(res[,,2]))]
m = glmnet(emb, labels$out_of_scope, family = "binomial", alpha = 0, lambda = best_lambda)

# APPLY ----

data = read_csv("Mapping_landscape_ABM/Data/data_cleaned_2.csv")

data_emb = model$encode(data$Abstract_cleaned)
for(i in 1:ncol(data_emb)) data_emb[,i] = z(data_emb[,i])

label = predict(m, newx = data_emb, type = "class") |> as.integer()
label = predict(m, newx = data_emb, type = "response") 

data_filtered = data |> filter(label == 0)

write_csv(data_filtered, "Mapping_landscape_ABM/Data/data_cleaned_filtered_2.csv")





