#' @export
#' @rdname sql_build
select_query <- function(from,
                         select = sql("*"),
                         where = character(),
                         group_by = character(),
                         having = character(),
                         window = character(),
                         order_by = character(),
                         limit = NULL,
                         distinct = FALSE) {

  stopifnot(is.character(select))
  stopifnot(is.character(where))
  stopifnot(is.character(group_by))
  stopifnot(is.character(having))
  stopifnot(is.character(window))
  stopifnot(is.character(order_by))
  stopifnot(is.null(limit) || (is.numeric(limit) && length(limit) == 1L))
  stopifnot(is.logical(distinct), length(distinct) == 1L)

  structure(
    list(
      from = from,
      select = select,
      where = where,
      group_by = group_by,
      having = having,
      window = window,
      order_by = order_by,
      distinct = distinct,
      limit = limit
    ),
    class = c("select_query", "query")
  )
}

#' @export
print.select_query <- function(x, ...) {
  cat(
    "<SQL SELECT",
    if (x$distinct) " DISTINCT", ">\n",
    sep = ""
  )
  cat_line("From:")
  cat_line(indent_print(sql_build(x$from)))

  if (length(x$select))   cat("Select:   ", named_commas(x$select), "\n", sep = "")
  if (length(x$where))    cat("Where:    ", named_commas(x$where), "\n", sep = "")
  if (length(x$group_by)) cat("Group by: ", named_commas(x$group_by), "\n", sep = "")
  if (length(x$window))   cat("Window:   ", named_commas(x$window), "\n", sep = "")
  if (length(x$order_by)) cat("Order by: ", named_commas(x$order_by), "\n", sep = "")
  if (length(x$having))   cat("Having:   ", named_commas(x$having), "\n", sep = "") # nocov
  if (length(x$limit))    cat("Limit:    ", x$limit, "\n", sep = "")
}

#' @export
sql_optimise.select_query <- function(x, con = NULL, ..., subquery = FALSE) {
  if (!inherits(x$from, "select_query")) {
    return(x)
  }

  from <- sql_optimise(x$from, subquery = subquery)

  # If all outer clauses are executed after the inner clauses, we
  # can drop them down a level
  outer <- select_query_clauses(x, subquery = subquery)
  inner <- select_query_clauses(from, subquery = TRUE)

  can_squash <- length(outer) == 0 || length(inner) == 0 || min(outer) > max(inner)

  if (can_squash) {
    # Have we optimised away an ORDER BY
    if (length(from$order_by) > 0 && length(x$order_by) > 0) {
      if (!identical(x$order_by, from$order_by)) {
        warn_drop_order_by()
      }
    }

    from[as.character(outer)] <- x[as.character(outer)]
    from
  } else {
    x$from <- from
    x
  }
}

# List clauses used by a query, in the order they are executed
# https://sqlbolt.com/lesson/select_queries_order_of_execution

# List clauses used by a query, in the order they are executed in
select_query_clauses <- function(x, subquery = FALSE) {
  present <- c(
    where =    length(x$where) > 0,
    group_by = length(x$group_by) > 0,
    having =   length(x$having) > 0,
    select =   !identical(unname(x$select), sql("*")),
    distinct = x$distinct,
    window = length(x$window) > 0,
    order_by = (!subquery || !is.null(x$limit)) && length(x$order_by) > 0,
    limit    = !is.null(x$limit)
  )

  ordered(names(present)[present], levels = names(present))
}

#' @export
sql_render.select_query <- function(query, con, ..., subquery = FALSE, lvl = 0) {
  from <- dbplyr_sql_subquery(con,
    sql_render(query$from, con, ..., subquery = TRUE, lvl = lvl + 1),
    name = NULL,
    lvl = lvl
  )

  dbplyr_query_select(
    con, query$select, from,
    where = query$where,
    group_by = query$group_by,
    having = query$having,
    window = query$window,
    order_by = query$order_by,
    limit = query$limit,
    distinct = query$distinct,
    ...,
    subquery = subquery,
    lvl = lvl
  )
}

warn_drop_order_by <- function() {
  # Rules according to SQLite: https://sqlite.org/forum/forumpost/878ca7a9be0862af?t=h
  # 1. There is no LIMIT clause in the subquery
  # 3. The subquery is not part of the FROM clause in an UPDATE-FROM statement
  # 4. The outer query does not use any aggregate functions other than the built-in count(), min(), and/or max() functions.
  # 5. Either the outer query has its own ORDER BY clause or else the subquery is one term of a join.
  #
  # (2. and 6. are left out as they are SQLite internal)
  warn(c(
    "ORDER BY is ignored in subqueries without LIMIT",
    i = "Do you need to move arrange() later in the pipeline or use window_order() instead?"
  ))
}
