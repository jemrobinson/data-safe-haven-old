# Example taken from:
# https://support.rstudio.com/hc/en-us/articles/200486088-Using-Rcpp-with-RStudio

# If Rcpp was succesfully installed, the example below should run with no errors
# Note: line 10 assumes that 'convolve.cpp' file is contained in the current 
# working directory 

library(Rcpp)

sourceCpp("convolve.cpp")
convolveCpp(x, y)