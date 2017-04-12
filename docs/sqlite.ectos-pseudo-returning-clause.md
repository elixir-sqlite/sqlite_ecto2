## Overview

Ecto relies on a returning clause for its insert, update, and delete statements.  A returning clause in PostgreSQL looks like the following:
```
INSERT INTO distributors (did, dname) VALUES (DEFAULT, 'XYZ Widgets') RETURNING did;
```

The returning clause returns one or more values from each row that was inserted, updated, or deleted with the statement.  SQLite lacks such a clause, but because Ecto uses it often, we must find a way to implement it in `sqlite_ecto2`. (Actually, the `RETURNING` clause is now [implemented by `sqlitex`](https://github.com/mmmries/sqlitex/pull/55).)

## Approach One:  Last Insert Rowid

During my experimentation with Ecto, I only noticed one use of the returning clause -- to return the ID for a row.  SQLite provides a function for returning the last ID that was created due to an insert statement (`last_insert_rowid()` in SQL and `sqlite3_last_insert_rowid()` in the C library).  However, there are a number of drawbacks to this method of returning values:

* The function only returns ID for inserts.  Updates and deletes would still require a different method.
* The function requires another select statement to return the ID of the inserted row.  If another row is inserted before the select statement to return the last ID, then the value might be wrong.
* Ecto *may* only use the returning statement for getting IDs from rows **today**, but I don't want my `sqlite_ecto2` adapter to rely on an undocumented "feature" of Ecto that may change in the future.

None of these reasons preclude me from utilizing the `last_insert_rowid()` function, but another method will need to be used as well.

## Approach Two:  Secondary Select Statements

Since we know the rows we are updating and deleting (and we can get the rowid of new rows we are inserting), we can issue a select statement before or after statements.

Deletes might look something like this:
```
DELETE FROM table WHERE id = 3 RETURNING value;
```
which could be converted to:
```
SELECT value FROM table WHERE id = 3;
DELETE FROM table WHERE id = 3;
```

Updates:
```
UPDATE users SET password = 'CHANGE_ME' WHERE password = '' RETURNING id, username;
```
to:
```
SELECT id, username FROM users WHERE password = '';
UPDATE users SET password = 'CHANGE_ME' WHERE password = '';
```

And inserts:
```
INSERT INTO users (username, email, password) VALUES ('jazzyb', 'jazzyb@example.com', 'passw0rd') RETURNING id, column_with_default_value;
```
to:
```
INSERT INTO users (username, email, password) VALUES ('jazzyb', 'jazzyb@example.com', 'passw0rd');
SELECT id, column_with_default_value FROM users WHERE id IN (SELECT last_insert_rowid());
```

Furthermore, we could encapsulate the above statements in transactions/savepoints to prevent changes from happening before we could return the correct values from the selects.  This might work, but it requires a good bit of thought on our part to determine the best way to select values for different kinds of queries.  Take the following update for example:
```
UPDATE table SET a = 1, b = 2 WHERE b = 3 RETURNING a, b, c;
```

What is the best way to rewrite it as we have done previously?  Well, even though the where clause tells us which rows will be changed, we have to be mindful of which columns are being updated by the call.  We can't execute the select statement after the call because there may have been other rows where `b = 2` before the update that don't apply to our returning clause.  If we execute the select statement before the update, then we have to anticipate what the new values in the returning clause will be.  It becomes:
```
SELECT 1, 2, c FROM table WHERE b = 3;
UPDATE table SET a = 1, b = 2 WHERE b = 3;
```

It seems possible to implement the returning clause this way, but working out the logic might not worth our time.  Fortunately, there is a better way.

## Approach Three (and Solution):  Triggers

[Triggers](https://www.sqlite.org/lang_createtrigger.html) are SQL database operations which can be automatically performed when a specified event occurs -- such as an insert, update, or delete on a particular table.  Triggers can access values from a row before or after a statement has been executed.  The solution we use in `sqlite_ecto2` to implement the returning clause is the following algorithm (English explanation follows):

```
SAVEPOINT sp_temp;
CREATE TEMP TABLE temp.t_temp (col1, col2, ...);
CREATE TEMP TRIGGER tr_temp AFTER UPDATE ON main.tablename BEGIN
    INSERT INTO t_temp SELECT NEW.col1, NEW.col2, ...;
END;
UPDATE ...;                              -- this is our statement to execute
DROP TRIGGER tr_temp;
SELECT col1, col2, ... FROM temp.t_temp; -- these results get saved
DROP TABLE temp.t_temp;
RELEASE sp_temp;
```

1. First, we create a savepoint so that if anything bad happens we can rollback to our prior state.  We use a savepoint instead of a transaction because Ecto issues these statements in transactions, and transactions, unlike savepoints, cannot be nested.
2. Next, we create a temporary table whose rows contain only the columns we want to return -- `col1`, `col2`, etc. in this example.
3. Then, we create a temporary trigger which fires after every update on `tablename`.  Of course, this assumes the statement is an update.  Inserts and deletes are declared respectively.  The body of the trigger says to insert the `NEW` values of the row into the temporary table.  Inserts also use `NEW`, but deletes specify `OLD`.
4. Once all the safety nets are in place, we execute our statement -- in this case an update.
5. Remove the temporary trigger.
6. Execute a select statement on the rows saved in the temporary table to get the return values.
7. Remove the temporary table once we have the results.
8. And finally, commit the changes.

The advantage of this method is that we don't have to anticipate what values are getting changed for what rows and how they are changing.  We just let SQLite do the work for us, and we reap the results.

### Caveat

There is an important disadvantage to using triggers to implement returning:  **SQLite triggers have an arbitrary order of execution.**  This means that if one has user-defined triggers that change inserted/updated column values, those changes may not be reflected in the returned values because we cannot guarantee that our temporary trigger will fire last.  However, if your application is relying on user-defined triggers, then you probably need a more robust database solution (like Postgres), and SQLite is not for you.  Thus, I believe this is a disadvantage worth having if it means implementing the same functionality as other adapters.

## Syntax of the Returning Clause

There remains one tricky bit to how the *pseudo*-returning clause is implemented.  Ecto executes database commands in two steps:  (1) Call the adapter to convert an Ecto.Query into a SQL string and (2) invoke `Sqlite.Ecto2.Connection.query` with the SQL string.  This means that the only access we have to the returning values is in step (1), but the only place we can implement the above algorithm is in step (2).  Thus, we must add our own syntax to represent the returning clause as a part of the SQL string, then in step (2) we must parse the returning clause to reconstruct the columns to return.  The syntax of the returning clause is the following:
```
;--RETURNING ON [INSERT | UPDATE | DELETE] tablename,col1,col2,...
```

Since `;` ends a SQL statement and `--` begins a SQL comment, beginning the pseudo-returning clause with `;--` ensures that the string is still a valid SQLite statement.  The format also lets me easy split the string on `";--RETURNING ON "` to separate the original statement-to-execute from the columns (and table) that we want to return.
