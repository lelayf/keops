% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/common-set_options.R
\name{set_rkeops_option}
\alias{set_rkeops_option}
\title{Set up a specific compile or runtime options of \code{rkeops} in \code{R} global
options scope}
\usage{
set_rkeops_option(option, value)
}
\arguments{
\item{option}{string, name of the option to set up (see Details).}

\item{value}{whatever value to assign to the chosen option (see Details).}
}
\description{
The function \code{set_rkeops_option} allows to modify the value of a single
specific \code{rkeops} options in \code{R} global options scope.
}
\details{
\code{rkeops} uses two sets of options: compile options (see
\code{\link[rkeops:compile_options]{rkeops::compile_options()}}) and runtime options (see
\code{\link[rkeops:runtime_options]{rkeops::runtime_options()}}). These options define the behavior of \code{rkeops}
when compiling or when calling user-defined operators.

With the function \code{set_rkeops_option}, you can set up a specific \code{rkeops}
option among:
\itemize{
\item \code{rkeops} compile options: rkeops_dir\verb{(not recommended),}build_dir\verb{,  }src_dir\verb{(not recommended),}precision\verb{, }verbosity\verb{,  }use_cuda_if_possible\verb{, }col_major\verb{(not recommended),}debug`
\item \code{rkeops} runtime options: \code{tagCpuGpu}, \code{tag1D2D}, \code{tagHostDevice},
\code{device_id}
with a value that you provide in input.
}

To know which values are allowed for which options, you can check
\code{\link[rkeops:compile_options]{rkeops::compile_options()}} and \code{\link[rkeops:runtime_options]{rkeops::runtime_options()}}.
}
\examples{
\dontrun{
# to enable GPU computing
set_rkeops_option("tagCpuGpu", 1)
# to set up the GPU id used for computations
set_rkeops_option("device_id", 0)
}
}
\seealso{
\code{\link[rkeops:set_rkeops_options]{rkeops::set_rkeops_options()}}, \code{\link[rkeops:compile_options]{rkeops::compile_options()}},
\code{\link[rkeops:runtime_options]{rkeops::runtime_options()}},  \code{\link[rkeops:use_gpu]{rkeops::use_gpu()}}, \code{\link[rkeops:compile4gpu]{rkeops::compile4gpu()}},
\code{\link[rkeops:get_rkeops_options]{rkeops::get_rkeops_options()}}
}
\author{
Ghislain Durif
}
