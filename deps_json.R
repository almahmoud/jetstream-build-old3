#!/usr/local/bin/RScript
outputfile <- commandArgs(trailingOnly = TRUE)
BiocManager::install("BiocKubeInstall")
library(BiocKubeInstall)
deps <- BiocKubeInstall::pkg_dependencies("3.14")
library(jsonlite)
fileConn<-file(outputfile)
writeLines(prettify(toJSON(deps)), fileConn)
close(fileConn)
