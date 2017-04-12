The table below compares the different functionality available between the PostgreSQL adapter, SQLite adapter (`sqlite_ecto2`), and barebones SQLite.  Use it to determine what Ecto functionality you can use with `sqlite_ecto2` and whether or not you should consider a more robust database solution, e.g. PostgreSQL, for your application.  There are open issues to extend the functionality of `sqlite_ecto2`, and this table will be updated as they are implemented.

| Supported Functionality            | PostgreSQL | `sqlite_ecto2` |  SQLite
|:-----------------------------------|:----------:|:--------------:|:--------:
| Inner Joins                        |  **Yes**   |   **Yes**      | **Yes**
| (Left) Outer Joins                 |  **Yes**   |   **Yes**      | **Yes**
| Right Outer Joins                  |  **Yes**   |      No        |    No
| Full Outer Joins<sup>1</sup>       |  **Yes**   |      No        |    No
| Foreign Key Constraints<sup>2</sup>|  **Yes**   |   **Yes**      | Optional
| `RETURNING` Clause<sup>3</sup>     |  **Yes**   |   **Yes**      |    No
| Update/Delete w/ Joins<sup>4</sup> |  **Yes**   |      No        |    No
| `ALTER COLUMN`<sup>5</sup>         |  **Yes**   |      No        |    No
| `DROP COLUMN`<sup>5</sup>          |  **Yes**   |      No        |    No
| Locking Clause on Select           |  **Yes**   |      No        |    No

#### Notes

1. A "full outer join" first implements an inner join on two tables.  Then, for any rows from either table that are missing from the result set, it adds those rows to the result set filling in NULLs for any missing values.  There is [an issue](https://github.com/jazzyb/sqlite_ecto/issues/27) to implement this functionality in `sqlite_ecto2`.
2. In SQLite, foreign key constraints must be turned on explicitly for each new database connection with:  `PRAGMA foreign_keys = ON;`.  `sqlite_ecto2` does this by default for each connection.
3. PostgreSQL can return arbitrary values on `INSERT`, `UPDATE`, or `DELETE`.  For example, the statement `INSERT INTO customs (counter, visits) VALUES (10, 11) RETURNING id;` will insert the given values into the `customs` table and then return the `id` for the new row.  SQLite has no support for such a `RETURNING` clause, but it can return the last inserted "rowid" for a table.  This ability was [added to the `sqlitex` library](https://github.com/mmmries/sqlitex/pull/55) in version 1.2.0.  [This article](sqlite.ectos-pseudo-returning-clause.md) discusses the method.
4. There is [an issue](https://github.com/jazzyb/sqlite_ecto/issues/20) to implement `JOIN`s for `INSERT` and `UPDATE` statements.
5. SQLite does not support modifying or deleting rows in `ALTER TABLE` statements.  The SQLite docs describe [an algorithm](https://www.sqlite.org/lang_altertable.html) for implementing this functionality.  However, the algorithm will require changes to the way foreign key constraints are handled.  [This issue](https://github.com/jazzyb/sqlite_ecto/issues/21) is tracking the necessary changes to Sqlite.Ecto foreign key constraints.
