% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utils.R
\name{compile4cpu}
\alias{compile4cpu}
\title{Disable compilation of GPU-compatible user-defined operators}
\usage{
compile4cpu()
}
\description{
Set up \code{rkeops} compile options to compile user-defined operators that run
be computed on CPU.
}
\details{
\strong{Note:} Default behavior is to compile GPU-compatible operators thus, if
you do not modify \code{rkeops} options, you have to call the function
\code{compile4cpu} to disable GPU-support.

CPU-compatible operators cannot run on GPU.
}
\examples{
\dontrun{
compile4cpu()
}
}
\seealso{
\code{\link[rkeops:compile4gpu]{rkeops::compile4gpu()}}, \code{\link[rkeops:use_cpu]{rkeops::use_cpu()}}
}
\author{
Ghislain Durif
}
