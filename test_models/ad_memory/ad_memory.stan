// One gradient of this model records N variables in the autodiff memory.
data {
  int<lower=0> N;
}
transformed data {
  vector[N] x = linspaced_vector(N, 0, 1);
}
parameters {
  real mu;
}
model {
  target += -0.5 * dot_self(mu + x);
}
