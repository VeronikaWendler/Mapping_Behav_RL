#include <RcppArmadillo.h>
#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::depends(RcppArmadillo)]]

// [[Rcpp::export]]
arma::mat arma_cosine(const arma::mat &mat){
  arma::mat cosines = mat * mat.t();
  arma::mat square = mat % mat;
  arma::colvec b = sum(square,1);
  arma::mat denum = sqrt(b) * sqrt(b.t());
  return cosines / denum;
  }

// [[Rcpp::export]]
arma::sp_mat cosine_sparse(const arma::sp_mat &mat){
  if (mat.n_rows == 0 || mat.n_cols == 0) {
    return arma::sp_mat(); // Return empty sparse matrix
  }
  
  arma::sp_mat cosines = mat * mat.t();
  arma::sp_mat sp_square = mat % mat;
  arma::colvec norms_squared = arma::zeros<arma::colvec>(mat.n_rows);
  arma::sp_mat::const_iterator it_sq     = sp_square.begin();
  arma::sp_mat::const_iterator it_sq_end = sp_square.end();
  
  for(; it_sq != it_sq_end; ++it_sq) {
    norms_squared(it_sq.row()) += (*it_sq);
  }
  
  arma::colvec norms = sqrt(norms_squared);
  arma::sp_mat::iterator it_cos     = cosines.begin();
  arma::sp_mat::iterator it_cos_end = cosines.end();
  
  for(; it_cos != it_cos_end; ++it_cos) {
    arma::uword row = it_cos.row();
    arma::uword col = it_cos.col();
    if (row >= norms.n_elem || col >= norms.n_elem) {
      Rcpp::warning("Row or column index out of bounds for norms vector. Skipping element (%d, %d).", row, col);
      (*it_cos) = 0; // Set to 0 or handle as error
      continue;
    }
    
    double norm_i = norms(row);
    double norm_j = norms(col);
    
    double den = norm_i * norm_j;
    if (den != 0) {
      (*it_cos) /= den;
    } else {
      (*it_cos) = 0;
    }
  }
  
  return cosines;
}

// [[Rcpp::export]]
arma::mat pmi(const arma::mat &G){
  arma::mat pmi = G / arma::accu(G);
  pmi /= (arma::sum(pmi, 1) * arma::sum(pmi, 0));
  return arma::log2(pmi);
}

// [[Rcpp::export]]
arma::mat ppmi(const arma::mat &G){
  arma::mat pmi_mat = pmi(G);
  pmi_mat.elem( find(pmi_mat < 0.0) ).zeros();
  return pmi_mat;
}

// [[Rcpp::export]]
arma::sp_mat ppmi_sparse(const arma::sp_mat &G){ // Renamed for clarity
  if (G.n_elem == 0 || arma::accu(G) == 0) {
    Rcpp::warning("Input matrix G is empty or sums to zero.");
    return arma::sp_mat(G.n_rows, G.n_cols);
  }
  
  double total_sum = arma::accu(G); // Calculate total sum once
  arma::sp_mat p_xy = G / total_sum;
  
  // *** Manual Summation ***
  arma::vec p_x(G.n_rows, arma::fill::zeros);
  arma::rowvec p_y(G.n_cols, arma::fill::zeros);
  arma::sp_mat::const_iterator it_g      = G.begin();
  arma::sp_mat::const_iterator it_g_end = G.end();
  for(; it_g != it_g_end; ++it_g) {
    double G_val = (*it_g);
    p_x(it_g.row()) += G_val;
    p_y(it_g.col()) += G_val;
  }
  p_x /= total_sum;
  p_y /= total_sum;
  // *** End Manual Summation ***
  
  
  // Create the result sparse matrix for PPMI
  arma::sp_mat ppmi_result(G.n_rows, G.n_cols);
  
  // Iterator approach for calculating log2(PMI) and applying max(0, ...)
  arma::sp_mat::const_iterator it_pxy      = p_xy.begin();
  arma::sp_mat::const_iterator it_pxy_end = p_xy.end();
  
  for(; it_pxy != it_pxy_end; ++it_pxy) {
    double val_pxy = (*it_pxy);
    arma::uword r = it_pxy.row();
    arma::uword c = it_pxy.col();
    
    // Check bounds (good practice) - Note: Using G.n_rows/G.n_cols for safety
    if (r >= G.n_rows || c >= G.n_cols) {
      Rcpp::Rcerr << "Warning: Index out of bounds during lookup."
                  << " Row: " << r << " Col: " << c << std::endl;
      continue;
    }
    
    double val_px = p_x(r);
    double val_py = p_y(c);
    
    if (val_pxy > 0 && val_px > 0 && val_py > 0) {
      double pmi_ratio = val_pxy / (val_px * val_py);
      // Check for potential numerical issues leading to ratio <= 0, though unlikely here
      if (pmi_ratio > 0) {
        double log_pmi_val = std::log2(pmi_ratio);
        // *** This is the PPMI step ***
        if (log_pmi_val > 0.0) {
          ppmi_result(r, c) = log_pmi_val;
          // Otherwise, it remains 0 in the sparse matrix, achieving max(0, pmi)
        }
      }
      // Optional: else case if pmi_ratio <= 0 needed handling (e.g., print warning)
    }
  }
  
  return ppmi_result; // Return the sparse PPMI matrix
}

// [[Rcpp::export]]
NumericVector maxs_r(const arma::mat &m){
  int n = m.n_rows;
  NumericVector maxs(n);
  for(int i = 0; i < n; ++i){
    maxs[i] = max(m.row(i));
  }
  return maxs;
}

// [[Rcpp::export]]
NumericVector maxs_c(const arma::mat &m){
  int n = m.n_cols;
  NumericVector maxs(n);
  for(int i = 0; i < n; ++i){
    maxs[i] = max(m.col(i));
  }
  return maxs;
}

// [[Rcpp::export]]
bool pnpoly(const arma::rowvec& point, const arma::mat& bp) {
  // Implementation of the ray-casting algorithm is based on
  // 
  unsigned int i, j;
  
  double x = point(0), y = point(1);
  
  bool inside = false;
  for (i = 0, j = bp.n_rows - 1; i < bp.n_rows; j = i++) {
    double xi = bp(i,0), yi = bp(i,1);
    double xj = bp(j,0), yj = bp(j,1);
    
    // See if point is inside polygon
    inside ^= (((yi >= y) != (yj >= y)) && (x <= (xj - xi) * (y - yi) / (yj - yi) + xi));
  }
  
  // Is the cat alive or dead?
  return inside;
}

#include <RcppArmadillo.h>
#include <cmath>      // For std::pow, std::log2
#include <algorithm>  // For std::max, std::min

// [[Rcpp::depends(RcppArmadillo)]]

// [[Rcpp::export]]
arma::sp_mat ppmi_sparse_sens(const arma::sp_mat &G, double row_sensitivity = 1.0, double col_sensitivity = 1.0){
  if (G.n_elem == 0 || arma::accu(G) == 0) {
    Rcpp::warning("Input matrix G is empty or sums to zero.");
    return arma::sp_mat(G.n_rows, G.n_cols);
  }
  
  // Clamp sensitivities to the range [0, 1]
  if (row_sensitivity < 0.0 || row_sensitivity > 1.0) {
    Rcpp::warning("row_sensitivity (%.2f) out of [0,1] range. Clamping.", row_sensitivity);
    row_sensitivity = std::max(0.0, std::min(1.0, row_sensitivity));
  }
  if (col_sensitivity < 0.0 || col_sensitivity > 1.0) {
    Rcpp::warning("col_sensitivity (%.2f) out of [0,1] range. Clamping.", col_sensitivity);
    col_sensitivity = std::max(0.0, std::min(1.0, col_sensitivity));
  }
  
  double total_sum = arma::accu(G); // Calculate total sum once
  arma::sp_mat p_xy = G / total_sum;
  
  // Calculate marginal probabilities P(x) and P(y)
  arma::vec p_x(G.n_rows, arma::fill::zeros);
  arma::rowvec p_y(G.n_cols, arma::fill::zeros); // Use rowvec for p_y for consistency in type with arma::sum(G,0)
  
  // Manual summation for marginals from G (original matrix with counts/values)
  arma::sp_mat::const_iterator it_g     = G.begin();
  arma::sp_mat::const_iterator it_g_end = G.end();
  for(; it_g != it_g_end; ++it_g) {
    double G_val = (*it_g);
    p_x(it_g.row()) += G_val;
    p_y(it_g.col()) += G_val;
  }
  p_x /= total_sum;
  p_y /= total_sum;
  
  // Create the result sparse matrix for PPMI
  arma::sp_mat ppmi_result(G.n_rows, G.n_cols);
  
  // Iterator approach for calculating log2(PMI) and applying max(0, ...)
  arma::sp_mat::const_iterator it_pxy     = p_xy.begin();
  arma::sp_mat::const_iterator it_pxy_end = p_xy.end();
  
  for(; it_pxy != it_pxy_end; ++it_pxy) {
    double val_pxy = (*it_pxy); // This is P(x,y)
    arma::uword r = it_pxy.row();
    arma::uword c = it_pxy.col();
    
    // P(x,y) must be positive for PMI to be meaningful and non-negative for PPMI
    if (val_pxy <= 0.0) {
      continue;
    }
    
    double val_px = p_x(r); // This is P(x)
    double val_py = p_y(c); // This is P(y)
    
    double term_px;
    if (row_sensitivity == 0.0) {
      term_px = 1.0; // P(x)^0 = 1, effectively ignoring row normalization
    } else {
      // If P(x) is 0 and sensitivity is applied, PMI is undefined. Skip.
      if (val_px <= 0.0) { 
        continue;
      }
      term_px = std::pow(val_px, row_sensitivity);
    }
    
    double term_py;
    if (col_sensitivity == 0.0) {
      term_py = 1.0; // P(y)^0 = 1, effectively ignoring column normalization
    } else {
      // If P(y) is 0 and sensitivity is applied, PMI is undefined. Skip.
      if (val_py <= 0.0) {
        continue;
      }
      term_py = std::pow(val_py, col_sensitivity);
    }
    
    // term_px and term_py are now guaranteed to be positive if we reached here.
    // (either 1.0 if sensitivity is 0, or pow(positive, sens) if sensitivity > 0)
    double pmi_denominator = term_px * term_py;
    
    // Since val_pxy > 0 and pmi_denominator > 0, pmi_ratio will be > 0.
    double pmi_ratio = val_pxy / pmi_denominator;
    
    // log2 is now safe as pmi_ratio > 0
    double log_pmi_val = std::log2(pmi_ratio);
    
    // PPMI step: store only if log_pmi_val is positive
    if (log_pmi_val > 0.0) {
      ppmi_result(r, c) = log_pmi_val;
    }
  }
  
  return ppmi_result; // Return the sparse PPMI matrix
}

