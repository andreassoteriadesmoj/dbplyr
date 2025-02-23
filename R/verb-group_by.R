#' Group by one or more variables
#'
#' This is a method for the dplyr [group_by()] generic. It is translated to
#' the `GROUP BY` clause of the SQL query when used with
#' [`summarise()`][summarise.tbl_lazy] and to the `PARTITION BY` clause of
#' window functions when used with [`mutate()`][mutate.tbl_lazy].
#'
#' @inheritParams arrange.tbl_lazy
#' @inheritParams dplyr::group_by
#' @param .drop Not supported by this method.
#' @param add Deprecated. Please use `.add` instead.
#' @export
#' @importFrom dplyr group_by
#' @examples
#' library(dplyr, warn.conflicts = FALSE)
#'
#' db <- memdb_frame(g = c(1, 1, 1, 2, 2), x = c(4, 3, 6, 9, 2))
#' db %>%
#'   group_by(g) %>%
#'   summarise(n()) %>%
#'   show_query()
#'
#' db %>%
#'   group_by(g) %>%
#'   mutate(x2 = x / sum(x, na.rm = TRUE)) %>%
#'   show_query()
group_by.tbl_lazy <- function(.data, ..., .add = FALSE, add = NULL, .drop = TRUE) {
  dots <- partial_eval_dots(.data, ..., .named = FALSE)

  if (!missing(add)) {
    lifecycle::deprecate_warn("1.0.0", "dplyr::group_by(add = )", "group_by(.add = )")
    .add <- add
  }

  if (!identical(.drop, TRUE)) {
    cli_abort("{.arg .drop} is not supported with database backends")
  }

  groups <- dplyr::group_by_prepare(.data, !!!dots, .add = .add, error_call = current_call())
  names <- purrr::map_chr(groups$groups, as_string)

  same_groups <- setequal(groups$group_names, group_vars(.data))
  if (same_groups) {
    return(groups$data)
  }

  groups$data$lazy_query <- add_group_by(groups$data, names)
  groups$data
}

# ungroup -----------------------------------------------------------------

#' @importFrom dplyr ungroup
#' @export
ungroup.tbl_lazy <- function(x, ...) {
  if (missing(...)) {
    group_by(x)
  } else {
    old_groups <- group_vars(x)
    to_remove <- fix_call(tidyselect::vars_select(op_vars(x), ...))
    new_groups <- setdiff(old_groups, to_remove)
    group_by(x, !!!syms(new_groups))
  }
}

add_group_by <- function(.data, group_vars) {
  .data$lazy_query$group_vars <- group_vars
  .data$lazy_query
}
