---
title: "Postgres Faceting - Part Three"
date: 2023-06-18
---

# Postgres Faceting - Part Three

This week's post is the final part (for now) in my Postgres Faceting Journey. If you're still catching up on that journey itself, or need a reminder of the context, I'd encourage you to go back and read through the first two parts (linked below).

- [Postgres Faceting - Part One](https://edbrown23.github.io/blog/2023/05/21/postgres-faceting-part-one)(where we motivate and setup this work)
- [Postgres Faceting - Part Two](https://edbrown23.github.io/blog/2023/06/04/postgres-faceting-part-two)(where we build out the necessary Postgres functionality for this week's post)

In this post, we're going to focus on actually using my new Postgres Full Text search column to enable faceting! Specifically, I need the efficient ability to count `Recipe.tags` across my entire collection of cocktails, and then to be able to filter that list of cocktails by tags such that I end up with a narrower set of tag counts that meet my requirements. 

As a limited example, if my entire collection was just two drinks, the Last Word and the Gin and Tonic (with lime juice, for examples sake), I might expect the following facets:

```
- gin (2)
- lime_juice (2)
- tonic (1)
- green_chartreuse (1)
- maraschino_liquor (1)
```

If I apply a filter on `tonic`, then my facets should now simply be:

```
filter == 'tonic'
- gin (1)
- tonic (1)
- lime_juice (1)
```

All facets are now "1's" because I've effectively filtered my collection to only the Gin and Tonic.

From a UX perspective, why do I want this? Because I've often found myself looking for interesting ways to combine ingredients, and these sorts of searches enable that exploration. If I filter my growing collection of cocktails to `bourbon` drinks and see there's a drink out there that combines `bourbon` _and_ `tequila`, now I'm interested ([And To All A Goodnight](https://barkeep.website/shared_cocktails/11), if you're curious. I didn't think it was very good...).

## Utilizing Postgres's built in tools

Month's ago, when I was first thinking about this project, I stumbled onto this [post](https://bun.uptrace.dev/postgres/faceted-full-text-search-tsvector.html#retrieving-document-stats) on faceted full text search in Postgres, and I knew from that point on that what I wanted to do here was possible (I also learned how long it takes to motivate any side-project effort that's larger than a few lines...). The key insight from that post is the Postgres function [ts_stat](https://www.postgresql.org/docs/current/textsearch-features.html#TEXTSEARCH-STATISTICS), which is able to consume a sql query and return statistics on the tsvector supplied to the query.

Let's look at some example output from this query to see how it meets my needs.

```sql
barkeep_development=# select word, ndoc from ts_stat($$ select searchable from recipes $$) order by ndoc desc;
                word                | ndoc
------------------------------------+------
 simple/syrup                       |   54
 angostura/bitters                  |   54
 lemon/juice                        |   53
 lime/juice                         |   53
 london/dry/gin                     |   39
 absinthe                           |   36
 sweet/vermouth                     |   30
 orange/bitters                     |   29
 rye                                |   29
 orange/peel                        |   24
 ... remainder elided for convenience
```

Based on the hoisting of tags I did over the last few posts, this is exactly what I need! And will it handle filtered queries? Yes! Check it out:

```sql
barkeep_development=# select word, ndoc from ts_stat($$ select searchable from recipes where searchable @@ 'cognac'::tsquery $$) order by ndoc desc;
          word           | ndoc
-------------------------+------
 cognac                  |   14
 orange/peel             |    6
 angostura/bitters       |    6
 simple/syrup            |    4
 lemon/juice             |    4
 nutmeg                  |    3
 vanilla                 |    3
```

And I can keep adding filters and things keep on filtering:

```sql
barkeep_development=# select word, ndoc from ts_stat($$ select searchable from recipes where searchable @@ 'cognac & absinthe'::tsquery $$) order by ndoc desc;
      word       | ndoc
-----------------+------
 creme/de/menthe |    1
 cognac          |    1
 absinthe        |    1
(3 rows)
```

Is this actually fast, or at least efficient? I'm not 100% sure, honestly, and if anyone reading this knows how to tell please reach out! I can say the subquery _should_ be performant, based on it hitting the `searchable` index we created last time.

```sql
barkeep_development=# explain analyze select searchable from recipes where searchable @@ 'cognac & absinthe'::tsquery;
                                                             QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on recipes  (cost=12.01..18.46 rows=2 width=74) (actual time=0.105..0.134 rows=1 loops=1)
   Recheck Cond: (searchable @@ '''cognac'' & ''absinthe'''::tsquery)
   Heap Blocks: exact=1
   ->  Bitmap Index Scan on index_recipes_on_searchable  (cost=0.00..12.01 rows=2 width=0) (actual time=0.024..0.030 rows=1 loops=1)
         Index Cond: (searchable @@ '''cognac'' & ''absinthe'''::tsquery)
 Planning Time: 0.100 ms
 Execution Time: 0.201 ms
(7 rows)
```

The `ts_stat` query, however, only shows me an opaque "Function Scan" line, which ultimately isn't that surprising given that we're using a PG function in the first place.

```sql
barkeep_development=# explain analyze select word, ndoc from ts_stat($$ select searchable from recipes where searchable @@ 'cognac & absinthe'::tsquery $$) order by ndoc desc;
                                                    QUERY PLAN
-------------------------------------------------------------------------------------------------------------------
 Sort  (cost=764.41..789.41 rows=10000 width=36) (actual time=0.291..0.332 rows=3 loops=1)
   Sort Key: ndoc DESC
   Sort Method: quicksort  Memory: 25kB
   ->  Function Scan on ts_stat  (cost=0.03..100.03 rows=10000 width=36) (actual time=0.226..0.255 rows=3 loops=1)
 Planning Time: 0.047 ms
 Execution Time: 0.398 ms
(6 rows)
```

Certainly for this small collection of recipes, the execution time should work just fine. The only concerning thing I can imagine from this `explain analyze` is the query planner's evident inability to predict the number of rows in the actual output, but my instinct is that this will be fine for awhile.

## Using facets in my app

Now that I can facet in sql, I need to integrate this into my actual application. Let's walk through that process. First of all, ActiveRecord has no means that I'm aware of for running these `ts_stat` queries, and my Full Text Search gem, `pg_search`, makes no reference to `ts_stat` anywhere in its code. So, I'm left to essentially run the same queries I wrote above in the context of my controllers.

Thankfully, this is easily done. I just need to construct the query based on the user's input and then pretty up the returned data for easier use in my views. I'll paste in my code for doing this below, and we'll walk through it together (and critique it!).

```ruby
tag_string = @tags_search&.map { |t| t.gsub('_', '/') }&.join(' & ')
id_string = "(#{initial_scope.pluck(:id).join(', ')})"

subquery = "SELECT searchable FROM recipes where id in #{id_string}"
if tag_string.present?
  subquery = subquery + "and searchable @@ '#{tag_string}'::tsquery"
end

raw_sql = "select word, ndoc from ts_stat($$ #{subquery} $$) order by ndoc desc;"
if initial_scope.pluck(:id).count > 0
  raw_facets = ActiveRecord::Base.connection.execute(raw_sql)
  @processed_facets = raw_facets.entries.index_by { |f| f['word'] }
else
  @processed_facets = {}
end
```

Astute readers among you are going to notice the small potential for SQL injection here, which we'll fix by the end of this post. However, as a starting point the above code does work.

First up, we construct the subquery (and introduce the SQL injection):
```ruby
tag_string = @tags_search&.map { |t| t.gsub('_', '/') }&.join(' & ')
id_string = "(#{initial_scope.pluck(:id).join(', ')})"

subquery = "SELECT searchable FROM recipes where id in #{id_string}"
if tag_string.present?
  subquery = subquery + "and searchable @@ '#{tag_string}'::tsquery"
end
```

Here we're turning the tags the user is filtering on into the a single tag string joined by ampersands. We're also limiting the set of returned recipes to those that the user's other filters have already reduced us to, like "only my recipes" and "recipes I have all the ingredients for".

```ruby
raw_sql = "select word, ndoc from ts_stat($$ #{subquery} $$) order by ndoc desc;"
if initial_scope.pluck(:id).count > 0
  raw_facets = ActiveRecord::Base.connection.execute(raw_sql)
  @processed_facets = raw_facets.entries.index_by { |f| f['word'] }
else
  @processed_facets = {}
end
```

Next up, we construct the final query itself, based on the queries we ran above. Then we do some checks to ensure that we don't run an invalid query, which is possible in this scenario because I'm constructing the SQL directly. I'm sure there's a nicer way to do this, but for now it works. Last but not least, we use ruby's `index_by` on the results to improve the interface to my facets, allowing me to access them as a dictionary of tags -> facet counts.

And we're done! But can we make this a little nicer, and avoid the SQL injection by routing the subquery generation to ActiveRecord? Let's give it a try.

### Where was the SQL Injection again?

Thank you, narrator, for asking such an apropos question. I think it would take jumping through a few hoops to actually execute a SQL injection exploit against this query, but theoretically it's possible and that's enough justification to try to better. In my case, the obvious hole is the construction of raw SQL based on user input. Specifically, this line:

```ruby
tag_string = @tags_search&.map { |t| t.gsub('_', '/') }&.join(' & ')
```

There's _some_ sanitation happening here based on the text manipulation and the `join`, but I'm sure someone smarter than me could still do something funky here. And this is all a bit ugly anyway since it repeats the underscore replacement logic from last week's post. We can do better (slightly).

Doing better in this case just means re-using the query we were already building for the rest of my view, the `initial_scope` you see above, in this facet query. In a sense this is obvious, because that scope already includes all of the user's other filters, and it already knows how to query by multiple tags via `pg_search`. So all I need to do is slightly modify it to only return the `searchable` tsvector column. Doing so is easy, and it reduces the full faceting logic down to only this:

```ruby
raw_sql = "select word, ndoc from ts_stat($$ #{initial_scope.select(:searchable).to_sql} $$) order by ndoc desc;"
if initial_scope.pluck(:id).count > 0
  raw_facets = ActiveRecord::Base.connection.execute(raw_sql)
  @processed_facets = raw_facets.entries.index_by { |f| f['word'] }
else
  @processed_facets = {}
end
```

Here I just use ActiveRecord's `select` method to limit what's returned by the query, and then use `to_sql` to plop in the raw sql I need, rather than execute the subquery directly. 

And we're done (again)! Despite the three posts it took us to get here, this really was easier than I expected it to be. If you want to see how this all comes together with the UI, and my lackluster UX capabilities, you can click around the [shared cocktails list](https://barkeep.website/shared_cocktails) without an account. And if you want to start tracking your own home bars and finding new drinks, email [me](eric.d.brown23@gmail.com) for an account!

## Conclusion

So what's next? I'm not entirely sure. There are many small UX improvements I can and should make, and those are likely what I'll work on next. How those will become blog posts is a problem for the future, but that future is a mere two weeks from now so we'll have to come up with something. Thanks for reading!

<hr>

Last week's post: [Postgres Faceting - Part Two](https://edbrown23.github.io/blog/2023/06/04/postgres-faceting-part-two)
