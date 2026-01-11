# libs
import numpy as np
import pandas as pd
from sentence_transformers import SentenceTransformer
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import log_loss, accuracy_score
from tqdm import trange


labels = pd.read_csv("data/filtering_labels.csv")

model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
emb = model.encode(labels["abstract"].tolist(), show_progress_bar=True)

# z-score features (column-wise)
scaler = StandardScaler()
emb = scaler.fit_transform(emb)

y = labels["out_of_scope"].values

nrun = 100
lambdas = np.exp(np.arange(-10, 11))
res_acc = np.zeros((nrun, len(lambdas)))
res_ll  = np.zeros((nrun, len(lambdas)))

rng = np.random.default_rng(42)

for i in trange(nrun):
    idx = rng.permutation(len(y))
    split = int(len(y) * 0.8)
    train_idx, test_idx = idx[:split], idx[split:]

    Xtr, Xte = emb[train_idx], emb[test_idx]
    ytr, yte = y[train_idx], y[test_idx]

    for j, lam in enumerate(lambdas):
        clf = LogisticRegression(
            penalty="l2",
            C=1/lam,            
            solver="lbfgs",
            max_iter=5000
        )
        clf.fit(Xtr, ytr)

        y_pred = clf.predict(Xte)
        y_prob = clf.predict_proba(Xte)[:,1]

        res_acc[i, j] = accuracy_score(yte, y_pred)
        res_ll[i, j]  = log_loss(yte, y_prob)


mean_ll = res_ll.mean(axis=0)
best_lambda = lambdas[np.argmin(mean_ll)]

print("Best lambda:", best_lambda)



final_clf = LogisticRegression(
    penalty="l2",
    C=1/best_lambda,
    solver="lbfgs",
    max_iter=5000
)
final_clf.fit(emb, y)



data = pd.read_csv("1_data/data_cleaned.csv")

data_emb = model.encode(
    data["Abstract_cleaned"].tolist(),
    show_progress_bar=True
)
data_emb = scaler.transform(data_emb)

probs = final_clf.predict_proba(data_emb)[:,1]
data["out_of_scope_prob"] = probs



data_filtered = data[data["out_of_scope_prob"] < 0.5]
data_filtered.to_csv("1_data/data_cleaned_filtered.csv", index=False)
