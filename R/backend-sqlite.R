#' Backend: SQLite
#'
#' @description
#' See `vignette("translation-function")` and `vignette("translation-verb")` for
#' details of overall translation technology. Key differences for this backend
#' are:
#'
#' * Uses non-standard `LOG()` function
#' * Date-time extraction functions from lubridate
#' * Custom median translation
#' * Right and full joins are simulated using left joins
#'
#' Use `simulate_sqlite()` with `lazy_frame()` to see simulated SQL without
#' converting to live access database.
#'
#' @name backend-sqlite
#' @aliases NULL
#' @examples
#' library(dplyr, warn.conflicts = FALSE)
#'
#' lf <- lazy_frame(a = TRUE, b = 1, c = 2, d = "z", con = simulate_sqlite())
#' lf %>% transmute(x = paste(c, " times"))
#' lf %>% transmute(x = log(b), y = log(b, base = 2))
NULL

#' @export
#' @rdname backend-sqlite
simulate_sqlite <- function() simulate_dbi("SQLiteConnection")

#' @export
dbplyr_edition.SQLiteConnection <- function(con) {
  2L
}

#' @export
db_connection_describe.SQLiteConnection <- function(con) {
  paste0("sqlite ", sqlite_version(), " [", con@dbname, "]")
}

#' @export
sql_query_explain.SQLiteConnection <- function(con, sql, ...) {
  build_sql("EXPLAIN QUERY PLAN ", sql, con = con)
}

#' @export
sql_query_set_op.SQLiteConnection <- sql_query_set_op.Hive

#' @export
sql_query_upsert.SQLiteConnection <- sql_query_upsert.PqConnection

sqlite_version <- function() {
  numeric_version(RSQLite::rsqliteVersion()[[2]])
}

# SQL methods -------------------------------------------------------------

#' @export
sql_translation.SQLiteConnection <- function(con) {
  sql_variant(
    sql_translator(.parent = base_scalar,
      as.numeric = sql_cast("REAL"),
      as.double = sql_cast("REAL"),
      log = function(x, base = exp(1)) {
        if (base != exp(1)) {
          sql_expr(log(!!x) / log(!!base))
        } else {
          sql_expr(log(!!x))
        }
      },
      paste = sql_paste_infix(" ", "||", function(x) sql_expr(cast(!!x %as% text))),
      paste0 = sql_paste_infix("", "||", function(x) sql_expr(cast(!!x %as% text))),
      # https://www.sqlite.org/lang_corefunc.html#maxoreunc
      pmin = sql_aggregate_n("MIN", "pmin"),
      pmax = sql_aggregate_n("MAX", "pmax"),

      # lubridate,
      today = function() {
        date <- function(x) {} # suppress R CMD check note
        sql_expr(date("now"))
      },
      now = function() sql_expr(datetime("now")),
      # https://modern-sql.com/feature/extract#proprietary-strftime
      year = function(x) sql_expr(cast(strftime("%Y", !!x) %as% NUMERIC)),
      month = function(x) sql_expr(cast(strftime("%m", !!x) %as% NUMERIC)),
      mday = function(x) sql_expr(cast(strftime("%d", !!x) %as% NUMERIC)),
      day = function(x) sql_expr(cast(strftime("%d", !!x) %as% NUMERIC)),
      hour = function(x) sql_expr(cast(strftime("%H", !!x) %as% NUMERIC)),
      minute = function(x) sql_expr(cast(strftime("%M", !!x) %as% NUMERIC)),
      second = function(x) sql_expr(cast(strftime("%f", !!x) %as% REAL)),
      yday = function(x) sql_expr(cast(strftime("%j", !!x) %as% NUMERIC)),

    ),
    sql_translator(.parent = base_agg,
      sd = sql_aggregate("STDEV", "sd"),
      median = sql_aggregate("MEDIAN"),
    ),
    if (sqlite_version() >= "3.25") {
      sql_translator(.parent = base_win,
        sd = win_aggregate("STDEV"),
        median = win_absent("median")
      )
    } else {
      base_no_win # nocov
    }
  )
}

#' @export
sql_escape_logical.SQLiteConnection <- function(con, x){
  y <- as.character(as.integer(x))
  y[is.na(x)] <- "NULL"
  y
}

#' @export
sql_query_wrap.SQLiteConnection <- function(con, from, name = NULL, ..., lvl = 0) {
  if (is.ident(from)) {
    setNames(from, name)
  } else {

    if (is.null(name)) {
      build_sql(sql_indent_subquery(from, con, lvl), con = con)
    } else {
      build_sql(sql_indent_subquery(from, con, lvl), " AS ", as_subquery_name(name), con = con)
    }
  }
}

#' @export
sql_expr_matches.SQLiteConnection <- function(con, x, y) {
  # https://sqlite.org/lang_expr.html#isisnot
  build_sql(x, " IS ", y, con = con)
}

#' @export
sql_query_join.SQLiteConnection <- function(con, x, y, vars, type = "inner", by = NULL, na_matches = FALSE, ..., lvl = 0) {
  # workaround as SQLite doesn't support FULL OUTER JOIN and RIGHT JOIN
  # see: https://www.sqlite.org/omitted.html

  if (type %in% c("left", "inner", "semi", "cross")) {
    return(NextMethod())
  }

  # as `x` and `y` the vars also need to be swapped in vars and by
  vars_right <- list(
    alias = vars$alias,
    x = vars$y,
    y = vars$x,
    all_x = vars$all_y,
    all_y = vars$all_x
  )
  by_right <- list(
    x = by$y,
    y = by$x,
    x_as = by$y_as,
    y_as = by$x_as
  )

  if (type == "full") {
    x_join <- sql_query_join(con, x, y, vars, type = "left", by = by, na_matches = na_matches, ..., lvl = lvl + 1)
    y_join <- sql_query_join(con, y, x, vars_right, type = "left", by = by_right, na_matches = na_matches, ..., lvl = lvl + 1)
    join_sql <- sql_query_set_op(
      con,
      x = x_join,
      y = y_join,
      method = "UNION",
      lvl = lvl + 1
    )

    sql_query_select(
      con,
      select = ident(vars$alias),
      from = dbplyr_sql_subquery(con, join_sql, lvl = lvl),
      subquery = TRUE,
      lvl = lvl
    )
  } else if (type == "right") {
    sql_query_join(con, y, x, vars_right, type = "left", by = by_right, na_matches = na_matches, ..., lvl = lvl)
  }
}

#' @export
values_prepare.SQLiteConnection <- function(con, df) {
  needs_escape <- purrr::map_lgl(df, ~ is(.x, "Date") || inherits(.x, "POSIXct"))
  purrr::modify_if(df, needs_escape, ~ escape(.x, con = con, parens = FALSE, collapse = NULL))
}

#' @export
supports_window_clause.SQLiteConnection <- function(con) {
  TRUE
}

globalVariables(c("datetime", "NUMERIC", "REAL"))
