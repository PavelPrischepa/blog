+++
date = "2020-06-13"
title = "Obfuscating database entity IDs in Postgres"
slug = "obfuscating-entity-ids-in-postgres"
tags = ["postgres"]
categories = ["development"]
+++

I was looking for a way of obfuscation database entity IDs and make it non-obvious for users.

Eventually, I found a very interesting approach described in ["Sharding & IDs at Instagram"](https://instagram-engineering.com/sharding-ids-at-instagram-1cf5a71e5a5c) post.
Approach described in that post based on generating obfuscated integer identifiers by a timestamp.
Generated identifiers could be sorted naturally from oldest to newest, and vice versa. 

That article is very interesting though it contains some minor problems that may make it difficult to understand it for beginners.

Here is my implementation of that approach.

## Creating `next_id()` function

Let is use the same Postgres function `next_id()` for all the tables:

```postgresql
CREATE FUNCTION next_id(sequence_name TEXT, OUT result BIGINT) AS
$$
DECLARE
	app_epoch_millis  BIGINT := 1577836800000; -- 2020-01-01 00:00:00
	seq_id     BIGINT;
	now_millis BIGINT;
BEGIN
	SELECT (nextval(sequence_name) - 1) % 1024 INTO seq_id; -- 1024 IDs per millisecond possible
	SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000) INTO now_millis;
	-- 10 bits for ID
	result := ((now_millis - app_epoch_millis) << 10) | (seq_id);
END;
$$ LANGUAGE plpgsql;
```

This function generates IDs using sequence name and current timestamp.

I use `BIGINT` field type for `id` fields in database tables. 
`BIGINT` is signed types of 64 bits (Postgres does not support unsigned `BIGINT`). 
As it is signed type, and I want positive values for IDs, I may use `64 - 1 = 63 bits` only.

Using this function I can generate up to 1024 ID per millisecond that is pretty enough. 
Storing up to 1024 IDs requires `10 bits`.

So 63 - 10 = 53 bits left for a timestamp.

### How long can I generate IDs this way before overflows 53 bits?

Let is calculate. 53 bits can hold:
- `(1<<53 - 1) = 9007199254740991 milliseconds`
- or `(1<<53 - 1) / 1000 = 9007199254740 seconds`
- or  `(1<<53 - 1) / 1000 / 86400 = 104249991 days`
- or  `(1<<53 - 1) / 1000 / 86400 / 365 = 285616 years`

Yeah, `285616 years` is pretty enough! 

In other words, I may generate 1024000 IDs per second per table for 285616 years.

Looks pretty enough for me.

## Creating tables
Let is create tables that will use `next_id()` function.   

Authors table: 
```postgresql
CREATE SEQUENCE author_id_seq AS BIGINT;
CREATE TABLE book
(
    id            		BIGINT       NOT NULL UNIQUE DEFAULT next_id('author_id_seq'),
    Name    			TEXT         NOT NULL
);
```

Books table:
```postgresql
CREATE SEQUENCE book_id_seq AS BIGINT;
CREATE TABLE book
(
    id            		BIGINT       NOT NULL UNIQUE DEFAULT next_id('book_id_seq'),
    title    			TEXT         NOT NULL,
    author_id          	BIGINT       NOT NULL
);
```

As you may see each table requires its own sequence. The name of the sequence passed as an argument to `next_id()` function.

**Do not reuse the same sequence in other tables!**

It is so easy to copy/paste a table creation snippet without changing a sequence name that passed to `next_id()` function and hard to fix such a mistake in a live environment when lots of IDs will be created.
  
## Other databases

This approach could be used in MySQL too and other databases that allow creating stored functions or procedures.
