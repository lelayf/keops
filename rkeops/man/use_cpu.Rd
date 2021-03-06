% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/utils.R
\name{use_cpu}
\alias{use_cpu}
\title{Disable GPU-computing when calling user-defined operators}
\usage{
use_cpu()
}
\description{
Set up \code{rkeops} runtime options to use CPU computing when calling
user-defined operators.
}
\details{
\strong{Note:} The default behavior in \code{rkeops} is to use CPU computing, thus
calling the function \code{use_gpu} is mandatory to run computations on GPU.

To enable GPU computing, run \code{\link[rkeops:use_gpu]{rkeops::use_gpu()}}.
}
\examples{
\dontrun{
use_cpu()
}
}
\seealso{
\code{\link[rkeops:compile4cpu]{rkeops::compile4cpu()}}, \code{\link[rkeops:compile4gpu]{rkeops::compile4gpu()}},
\code{\link[rkeops:use_gpu]{rkeops::use_gpu()}}
}
\author{
Ghislain Durif
}
