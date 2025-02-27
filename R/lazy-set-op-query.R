#' @export
#' @rdname sql_build
lazy_set_op_query <- function(x,
                              y,
                              type,
                              all,
                              call = caller_env()) {
  stopifnot(inherits(x, "lazy_query"))
  stopifnot(inherits(y, "lazy_query"))
  vctrs::vec_assert(type, character(), size = 1L, arg = "type", call = call)
  assert_flag(all)

  lazy_query(
    query_type = "set_op",
    x = x,
    y = y,
    type = type,
    all = all
  )
}

#' @export
print.lazy_set_op_query <- function(x, ..., con = NULL) {
  cat_line("<SQL ", toupper(x$type), ">")

  cat_line("X:")
  cat_line(indent_print(sql_build(x$x, simulate_dbi())))

  cat_line("Y:")
  cat_line(indent_print(sql_build(x$y, simulate_dbi())))
}

#' @export
op_vars.lazy_set_op_query <- function(op) {
  union(op_vars(op$x), op_vars(op$y))
}

#' @export
sql_build.lazy_set_op_query <- function(op, con, ...) {
  # add_op_set_op() ensures that both have same variables
  set_op_query(
    sql_optimise(sql_build(op$x, con), con),
    sql_optimise(sql_build(op$y, con), con),
    type = op$type,
    all = op$all
  )
}
