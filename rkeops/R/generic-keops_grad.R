#' Compute the gradient of a rkeops operator
#' @description
#' The function `keops_grad` defines a new operator that is a partial derivative 
#' from a previously defined KeOps operator supplied as input regarding a 
#' specified input variable of this operator.
#' @details
#' The use of the function `keops_grad` is detailed in the vignettes. 
#' Run `browseVignettes("rkeops")` to access the vignettes.
#' 
#' KeOps gradient operators are defined based on KeOps formula and on operator 
#' `Grad`. The function `keops_grad` is a wrapper to define a new formula 
#' deriving the gradient of the formula associated to a previously defined 
#' operator. The user just needs to choose regarding which variable (given by 
#' name or by position starting at 0), they want to compute the partial 
#' derivative.
#' 
#' The function `keops_grad` then calls the function [rkeops::keops_kernel()] 
#' to compile a new operator corresponding to the partial derivative of the 
#' input operator.
#' 
#' To decide regarding which variable the input operator should be derived,
#' you can specify its name or its position starting as 0 with the input 
#' parameter `var`. 
#' @author Ghislain Durif
#' @param operator a function returned by `keops_kernel` implementing a 
#' formula.
#' @param var a text string or an integer number indicating regarding to which 
#' variable/parameter (given by name or by position starting at 0) the 
#' gradient of the formula should be computed.
#' @return FIXME
#' @importFrom stringr str_match_all
#' @seealso [rkeops::keops_kernel()]
#' @examples
#' \dontrun{
#' formula <- "Sum_Reduction(SqNorm2(x-y), 0)"
#' args <- c("x=Vi(0,3)", "y=Vj(1,3)")
#' op <- keops_kernel(formula, args)
#' grad_op <- keops_grad(op, var=0)
#' }
#' @export
keops_grad <- function(operator, var) {
    # check input (string or integer)
    if(is.numeric(var)) var <- as.integer(var)
    if(length(var) > 1 & !is.character(var) & !is.integer(var)) 
        stop(paste0("`var` input argument should be the name (string) ", 
                    "or position (integer) of an argument in the formula"))
    # get operator context (formula, variable, etc.)
    env <- operator()
    # parse formula and args to derive position of new variable
    var_aliases <- env$var_aliases
    extra_var <- parse_extra_args(env$formula, env$args)
    # position new variable = length arg list - 1 (last)
    posnewvar <- max(c(var_aliases$var_pos, extra_var$var_pos)) + 1
    # define the new formula depending on var type
    new_formula <- NULL
    if(is.character(var)) {
        new_formula <- paste0("GradFromPos(", env$formula, ",", var, ",", 
                              posnewvar, ")")
        
        
    } else if(is.numeric(var)) {
        new_formula <- paste0("GradFromInd(", env$formula, ",", var, ",", 
                              posnewvar, ")")
    } else {
        stop("`var` input argument should be a text string or an integer.")
    }
    # define new op
    return(keops_kernel(new_formula, env$args))
}