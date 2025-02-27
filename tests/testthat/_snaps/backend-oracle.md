# queries translate correctly

    Code
      mf %>% head()
    Output
      <SQL>
      SELECT *
      FROM (`df`) 
      FETCH FIRST 6 ROWS ONLY

# `sql_query_upsert()` is correct

    Code
      sql_query_upsert(con = simulate_oracle(), x_name = ident("df_x"), y = df_y, by = c(
        "a", "b"), update_cols = c("c", "d"), returning_cols = c("a", b2 = "b"),
      method = "merge")
    Output
      <SQL> MERGE INTO `df_x`
      USING (
        SELECT `a`, `b`, `c` + 1.0 AS `c`, `d`
        FROM (`df_y`) 
      ) `...y`
        ON `...y`.`a` = `df_x`.`a` AND `...y`.`b` = `df_x`.`b`
      WHEN MATCHED THEN
        UPDATE SET `c` = `excluded`.`c`, `d` = `excluded`.`d`
      WHEN NOT MATCHED THEN
        INSERT (`c`, `d`)
        VALUES (`...y`.`c`, `...y`.`d`)
      RETURNING `df_x`.`a`, `df_x`.`b` AS `b2`
      ;

# generates custom sql

    Code
      sql_table_analyze(con, in_schema("schema", "tbl"))
    Output
      <SQL> ANALYZE TABLE `schema`.`tbl` COMPUTE STATISTICS

---

    Code
      sql_query_explain(con, sql("SELECT * FROM foo"))
    Output
      <SQL> EXPLAIN PLAN FOR SELECT * FROM foo;
      SELECT PLAN_TABLE_OUTPUT FROM TABLE(DBMS_XPLAN.DISPLAY()));

---

    Code
      left_join(lf, lf, by = "x", na_matches = "na")
    Output
      <SQL>
      SELECT `df_LHS`.`x` AS `x`
      FROM (`df`) `df_LHS`
      LEFT JOIN (`df`) `df_RHS`
        ON (decode(`df_LHS`.`x`, `df_RHS`.`x`, 0, 1) = 0)

---

    Code
      sql_query_save(con, sql("SELECT * FROM foo"), in_schema("schema", "tbl"))
    Output
      <SQL> CREATE GLOBAL TEMPORARY TABLE 
      `schema`.`tbl` AS
      SELECT * FROM foo

---

    Code
      sql_query_save(con, sql("SELECT * FROM foo"), in_schema("schema", "tbl"),
      temporary = FALSE)
    Output
      <SQL> CREATE TABLE 
      `schema`.`tbl` AS
      SELECT * FROM foo

# copy_inline uses UNION ALL

    Code
      copy_inline(con, y %>% slice(0)) %>% remote_query()
    Output
      <SQL> SELECT CAST(NULL AS INT) AS `id`, CAST(NULL AS VARCHAR2(255)) AS `arr`
      FROM (`DUAL`) 
      WHERE (0 = 1)
    Code
      copy_inline(con, y) %>% remote_query()
    Output
      <SQL> SELECT CAST(`id` AS INT) AS `id`, CAST(`arr` AS VARCHAR2(255)) AS `arr`
      FROM (
        (
          SELECT NULL AS `id`, NULL AS `arr`
          FROM (`DUAL`) 
          WHERE (0 = 1)
        )
        UNION ALL
        (SELECT 1, '{1,2,3}' FROM DUAL)
      ) `values_table`
    Code
      copy_inline(con, y %>% slice(0), types = types) %>% remote_query()
    Output
      <SQL> SELECT CAST(NULL AS bigint) AS `id`, CAST(NULL AS integer[]) AS `arr`
      FROM (`DUAL`) 
      WHERE (0 = 1)
    Code
      copy_inline(con, y, types = types) %>% remote_query()
    Output
      <SQL> SELECT CAST(`id` AS bigint) AS `id`, CAST(`arr` AS integer[]) AS `arr`
      FROM (
        (
          SELECT NULL AS `id`, NULL AS `arr`
          FROM (`DUAL`) 
          WHERE (0 = 1)
        )
        UNION ALL
        (SELECT 1, '{1,2,3}' FROM DUAL)
      ) `values_table`

