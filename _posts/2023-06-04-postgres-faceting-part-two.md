---
title: "Postgres Faceting - Part Two"
date: 2023-06-04
---

# Postgres Faceting - Part Two

This week is part two in my Postgres Faceting series, where I'll be tweaking my data model to improve the query-ability of my cocktail recipes. There will likely be one more post after this one, but if you missed the first and want the context, check it out below:

- [Postgres Faceting - Part One](https://edbrown23.github.io/blog/2023/05/21/postgres-faceting-part-one)
- Part Three coming soon...

Last time, we wrote a rake task to hoist my data from the one-to-many `ReagentAmount` models up to a `jsonb` column on my `Recipe` models. This week, we're going to enable search on that hoisted data.

## Gems and references

To enable the search functionality I'm going to need, first I need a gem that will wrap the requisite queries into ActiveRecord. Months back when I originally had the idea for this change some quick googling pointed me to [`pg_search`](https://github.com/Casecommons/pg_search), which is my choice now. `pg_search` seems well documented, there's plenty of references to it on StackOverflow, etc, so it seems like a safe choice. 

I've also been accruing blog posts on this topic for months, all of which have been very helpful. Pretty much all of the functionality in this series of posts will be inspired or even implemented by each:

- https://bun.uptrace.dev/postgres/faceted-full-text-search-tsvector.html
- https://pganalyze.com/blog/full-text-search-ruby-rails-postgres

## Creating a tsvector column

First up, we need a column on our `Recipe` table to store our search data. Technically, l think `pg_search` would be able to run queries like this without a dedicated column, but it's my understanding that that would require runtime analysis of all of my data for every query, which seems grossly inefficient. Luckily, Postgres and `pg_search` make it easy to avoid that inefficiency, as we'll see throughout this series of posts. What we need is a `tsvector` column to pair with our `ts_query`.

I'm going to paste in the entire migration to create this column below, and then we'll break it down piece by piece.

```ruby
class AddTextSearchToRecipes < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      CREATE FUNCTION extract_tags_from_blob(blob JSONB)
      RETURNS TEXT[] LANGUAGE SQL IMMUTABLE
      AS $$
        select
          array_agg(replace(tags, '_', '/'))
        from (
          select jsonb_array_elements_text(jsonb_array_elements(blob->'ingredients')->'tags') as tags
        ) t;
      $$;

      ALTER TABLE recipes
      ADD COLUMN searchable tsvector GENERATED ALWAYS AS (
        array_to_tsvector(extract_tags_from_blob(ingredients_blob))
      ) STORED;
    SQL
  end

  def down
    execute <<~SQL    
      DROP FUNCTION IF EXISTS extract_tags_from_blob(blob JSONB) RETURNS TEXT[];

      ALTER TABLE recipes DROP COLUMN searchable;
    SQL
  end
end
```

Let's start with the column itself. `tsvector`'s effectively store the post-analyzed state of the text you're trying to search. What that implies is that they don't contain any of their own data, but rather just an interpretation of another column or set of column's data. As such, they have to be "generated", and in my case they need to be filled with the `tags` from each `Recipe`'s `ingredients_blob`.

```sql
ALTER TABLE recipes
ADD COLUMN searchable tsvector GENERATED ALWAYS AS (
  array_to_tsvector(extract_tags_from_blob(ingredients_blob))
) STORED;
```

Generated columns require an expression telling PG how to create the column data. That's where `extract_tags_from_blob(ingredients_blob)` comes in. After last time each `Recipe` now contains it's own ingredient information in the following form:

```json
{
  "ingredients": [
    {
      "tags": [
        "green_chartreuse"
      ],
      "unit": "oz",
      "amount": "0.75",
      "reagent_amount_id": 17375
    },
    {
      "tags": [
        "gin"
      ],
      "unit": "oz",
      "amount": "0.75",
      "reagent_amount_id": 17376
    },
    {
      "tags": [
        "luxardo_marascino"
      ],
      "unit": "oz",
      "amount": "0.75",
      "reagent_amount_id": 17377
    },
    {
      "tags": [
        "lime_juice"
      ],
      "unit": "oz",
      "amount": "0.75",
      "reagent_amount_id": 17378
    }
  ]
}
```

I need to extract the array of `tags` on each object into a single array of all the tags for a `Recipe`. The following SQL function accomplishes this (plus some other things, which I'll get to):

```sql
CREATE FUNCTION extract_tags_from_blob(blob JSONB)
RETURNS TEXT[] LANGUAGE SQL IMMUTABLE
AS $$
  select
    array_agg(replace(tags, '_', '/'))
  from (
    select jsonb_array_elements_text(jsonb_array_elements(blob->'ingredients')->'tags') as tags
  ) t;
$$;
```

The `jsonb_array_elements*` functions do the real work for me here, taking the aforementioned JSON data and pulling it into a row per tag (id = 2444 is the id of one of my Last Word `Recipe`s):

```
barkeep_development=# select jsonb_array_elements_text(jsonb_array_elements(ingredients_blob->'ingredients')->'tags') as tags from recipes where id = 2444;
       tags
-------------------
 green_chartreuse
 gin
 luxardo_marascino
 lime_juice
```

This isn't exactly what I want though, I need these tags as a single row, rather than 4 separate rows. Here, `array_agg` does the trick, aggregating each row into a single row with the values as array elements.

```
barkeep_development=# select array_agg(tags) from (select jsonb_array_elements_text(jsonb_array_elements(ingredients_blob->'ingredients')->'tags') as tags from recipes where id = 2444) t;
                      array_agg
-----------------------------------------------------
 {green_chartreuse,gin,luxardo_marascino,lime_juice}
(1 row)
```

### Let's talk dictionaries

The last wrinkle in this migration is my handling of underscores. Why do I need this bit?

```sql
replace(tags, '_', '/')
```

I'm getting slightly out of order by handling this now, but part three will dig more into the usage of my new search functionality. For now, let's just look at how Postgres will allow me to query for one of those Last Word ingredients, `lime_juice`.

I can query for the tsvector version of my ingredient directly in psql, like so:

```sql
barkeep_development=# select to_tsvector('simple', 'lime_juice');
    to_tsvector
--------------------
 'juice':2 'lime':1
(1 row)
```

What's happened here? Well, in preparation for far more advanced full text queries, Postgres has used its `simple` [dictionary](https://www.postgresql.org/docs/current/textsearch-dictionaries.html) to parse the input string and turn it into more useful information, like token positions, and it has removed "whitespace" characters like the underscore. If I had used the `english` dictionary it would have done even more to normalize the tokens, like so:

```sql
barkeep_development=# select to_tsvector('english', 'lime_juice');
    to_tsvector
-------------------
 'juic':2 'lime':1
(1 row)
```

Here, it has "normalized" `juice` into `juic`, which will allow it to more easily match differently derived forms of that word, like the plural `juices`. 

All of this intelligence is bad for me though, because I _do_ want to search for the literal string `lime_juice`. So, I have to trick the parser into not tokenizing my input by replacing all of the underscores with forward slashes. As you can see below, this does the trick:

```sql
barkeep_development=# select to_tsvector('simple', 'lime/juice');
  to_tsvector
----------------
 'lime/juice':1
(1 row)
```

With all of this in place, I can take a single Recipe's ingredients blob and turn it into an array of parsed, `tsvector`-ized, tokens.

```sql
barkeep_development=# select array_to_tsvector(array_agg(replace(tags, '_', '/'))) from (select jsonb_array_elements_text(jsonb_array_elements(ingredients_blob->'ingredients')->'tags') as tags from recipes where id = 2444) t;
                     array_to_tsvector
-----------------------------------------------------------
 'gin' 'green/chartreuse' 'lime/juice' 'luxardo/marascino'
(1 row)
```

## Convincing Postgres of my good intentions

With the above implemented, you might ask why, beyond simple code organization reasons, this needs to be a separately defined `FUNCTION`, especially one marked as `IMMUTABLE`. It's not going to be used anywhere but here, so why bother splitting it out? There are a few reasons, but mostly it boils down to convincing Postgres that what I'm doing here is ok. 

Generated columns have a [few rules](https://www.postgresql.org/docs/current/ddl-generated-columns.html), first of which is "The generation expression can only use immutable functions and cannot use subqueries or reference anything other than the current row in any way." Now, I'm clearly using subqueries here, but I get away with it by putting the logic inside a function that I promise is `IMMUTABLE`. Plus, my "subqueries" aren't querying other tables, they're just reshaping data into an easier to manage view.

How about the `array_agg` function? Why does that need to be inside the `extract_tags_from_blob` definition? This one I don't entirely understand, but it seems to boil down to the context in which the aggregate function is run. If I move the usage of `array_agg` to inside the generation expression, I get the following error:

```
PG::GroupingError: ERROR:  aggregate functions are not allowed in column generation expressions
```

Googling around for this error returns a bunch of posts that are related to aggregate functions, but few that I can find that explicitly reference generation expressions. Something to learn another day. For now, moving my aggregate function usage inside an immutable function I defined and promised was legal was enough to trick Postgres into executing my migration, and I'm off to the races. 

## Querying my new column

We're going to get into the details of using this new column for real functionality next time, but since we've gotten this far we can look at how easy it now is to query for different combinations of tags. Using `pg_search`, I can define a search function for `Recipe`'s like so:

```ruby
pg_search_scope :private_by_tag, against: :searchable, using: { tsearch: { dictionary: :simple, tsvector_column: :searchable } }

scope :by_tag, ->(*tag_string) { private_by_tag(tag_string.map { |t| t.gsub('_', '/') }) }
```

`pg_search_scope` does the meat of the work, telling `pg_search` which column and dictionary to use when searching. To simplify the handling of underscores on the query side, I wrapped the gem's search function in a new scope which will replace all underscores on the way in.

With this scope in place, I can now easily search for any combination of ingredients by either chaining scopes or passing in an array (clearly my testing database is missing the Gimlet...):

```
irb(main):056:0> Recipe.by_tag('lime_juice').by_tag('gin').pluck(:name)
=> ["Last Word", "Naked & Famous"]
irb(main):057:0> Recipe.by_tag('lime_juice', 'gin').pluck(:name)
=> ["Last Word", "Naked & Famous"]
```

What's even better about this is that since `pg_search` uses scopes for this functionality, it trivially combines with my other scopes, like my `for_user` scope which queries for recipes owned by a particular user.

## How about an Index?

Things have been smooth so far, but how does this new column perform? I've already gone to some lengths to speed it up by using a generated `tsvector` column, but is that enough? Looking at some query plans, we can see that despite our new column, we're still doing a sequential scan, which is less than ideal:

```ruby
irb(main):029:0> Recipe.by_tags('campari').by_tags('bourbon').explain
=>
                                                                        QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=39.75..39.76 rows=1 width=707)
   Sort Key: (ts_rank(recipes_1.searchable, '''campari'''::tsquery, 0)) DESC, recipes.id, (ts_rank(recipes_2.searchable, '''bourbon'''::tsquery, 0)) DESC
   ->  Nested Loop  (cost=0.29..39.74 rows=1 width=707)
         ->  Nested Loop  (cost=0.15..38.72 rows=1 width=739)
               ->  Seq Scan on recipes recipes_1  (cost=0.00..30.50 rows=1 width=40)
                     Filter: (searchable @@ '''campari'''::tsquery)
               ->  Index Scan using recipes_pkey on recipes  (cost=0.15..8.17 rows=1 width=699)
                     Index Cond: (id = recipes_1.id)
         ->  Index Scan using recipes_pkey on recipes recipes_2  (cost=0.15..0.58 rows=1 width=40)
               Index Cond: (id = recipes.id)
               Filter: (searchable @@ '''bourbon'''::tsquery)
(11 rows)
```

How can I avoid future problems and speed this up? Turns out it's simple, I just need a GIN index on the `searchable` column.

```ruby
class AddGinIndexToSearchable < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :recipes, :searchable, using: :gin, algorithm: :concurrently
  end
end
```

With that index in place, the same query now produces the following plan:

```ruby
irb(main):001:0> Recipe.by_tags('campari').by_tags('bourbon').explain
=>
                                                                        QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=21.28..21.28 rows=1 width=707)
   Sort Key: (ts_rank(recipes_1.searchable, '''campari'''::tsquery, 0)) DESC, recipes.id, (ts_rank(recipes_2.searchable, '''bourbon'''::tsquery, 0)) DESC
   ->  Nested Loop  (cost=8.31..21.27 rows=1 width=707)
         ->  Nested Loop  (cost=8.16..20.25 rows=1 width=739)
               ->  Bitmap Heap Scan on recipes recipes_1  (cost=8.01..12.02 rows=1 width=40)
                     Recheck Cond: (searchable @@ '''campari'''::tsquery)
                     ->  Bitmap Index Scan on index_recipes_on_searchable  (cost=0.00..8.01 rows=1 width=0)
                           Index Cond: (searchable @@ '''campari'''::tsquery)
               ->  Index Scan using recipes_pkey on recipes  (cost=0.15..8.17 rows=1 width=699)
                     Index Cond: (id = recipes_1.id)
         ->  Index Scan using recipes_pkey on recipes recipes_2  (cost=0.15..0.58 rows=1 width=40)
               Index Cond: (id = recipes.id)
               Filter: (searchable @@ '''bourbon'''::tsquery)
(13 rows)
```

Look at that, hitting the index just as we hoped. Theoretically, this should now last me a good long time without major performance issues (famous last words, I know).

## What's next?

Phew, this turned into a long post. Lots of progress was made however! We've hoisted our data onto the `Recipe` models, added a performant new column that enables the queries I need, and ensured that querying that new column will continue to perform as more recipes are added. Next time, we'll actually use this new column in the app. See you soon!

<hr>

Last week's post: [Postgres Faceting - Part One](https://edbrown23.github.io/blog/2023/05/21/postgres-faceting-part-one)

