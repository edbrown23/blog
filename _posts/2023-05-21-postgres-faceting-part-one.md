---
title: "Postgres Faceting - Part One"
date: 2023-05-21
---

# Postgres Faceting - Part One

This week's post will be the first in a multipart story covering the next big data model conversion for [barkeep](https://barkeep.website). All the work will likely fit into two-ish posts, but as I write this I'm only starting to do the actual conversion so who knows really? The other posts in this series are linked here:

- [Postgres Faceting - Part Two](https://edbrown23.github.io/blog/2023/06/04/postgres-faceting-part-two)
- [Postgres Faceting - Part Three](https://edbrown23.github.io/blog/2023/06/18/postgres-faceting-part-three)

## Faceting, eh? Fascinating

To review, `barkeep`'s current data model relies on `Recipe` models which `has_many :reagent_amounts` (Rails naming conventions are ruining my grammar here). Those `ReagentAmount` models store the `tags` of a cocktail's particular ingredients plus the volume required. So that Last Word which can be based on either `gin` or `london_dry_gin` knows that via one of its `ReagentAmounts`.

This data model has worked fine for awhile, and would probably keep working if I didn't want to add faceting and filtering by combinations of ingredients (more on that later), but it does have some other general issues:

- When I update a `Recipe`, I just delete all the `ReagentAmount` models for that recipe first and make brand new ones. This is _fine_, and it's certainly easier than trying to retain the existing rows by diffing the change made by the user, but it feels a little wasteful
- It means that if I want to know all the tags associated with a recipe, I have to load several rows from the database
- Because of the above, when I need to query efficiently for which drinks a user can make I have to go from `ReagentAmount`s -> `Recipe`s. It's impossible to go in the reverse direction because I'd need to load every `Recipe'`s amounts first in order to have access to the `tags`, and then I'm back where I started.
- All of the above adds up to the fact that it's difficult to do AND queries on ingredient tags with my current model. Currently I can find all the `ReagentAmount`s that match `whiskey` and `sweet_vermouth`, for example, but those two amounts might refer to a Whiskey Sour and a Negroni (`whiskey` || `sweet_vermouth`), when all I wanted was a Boulevardier (`whiskey` && `sweet_vermouth`). 

And, most importantly, back to that "faceting" point: I want to be able to present to the user a more useful view into what cocktails they can currently make, split apart by which ingredients they have. Think the left side of an Amazon page, but for cocktail ingredients.

![amazon_faceting](/blog/docs/assets/2023-05-21/amazon_faceting.png)

In order to do that using only Postgres, I need to hoist all of the critical ingredient tagging information on the `Recipe` model itself. Once there, I believe I'll be able to run efficient counts of Recipes per tag using Postgres' full text search capabilities.

I hinted at this idea back in the [post about my data model](https://edbrown23.github.io/blog/2023/02/26/data-model-importance):

> - I'm not sure it's worth having separate `reagent_amount` models. I could probably just move the tags into blobs on the `recipe` model itself. The separate models are really just a hold out from the first data model anyway.
> - Doing the above would unlock faceting via PG, which I think is a feature I'll want pretty soon.

So, let's get into it.

## Hoisting the ingredient info

The first, partially self-induced, challenge of this project is doing it all in-place with the existing models. I could write a somewhat involved migration that iterated through all of the `ReagentAmount`s and wrote their information onto the `Recipe` model before deleting themselves and eventually the entire table. I've learned a valuable lesson in the year of working on barkeep however: don't start a massive data model migration that requires rewriting large portions of the application and expect to ship it all at once. I simply never dedicate enough time to barkeep in any one instance to complete such a migration, and the main lesson of my [data model post](https://edbrown23.github.io/blog/2023/02/26/data-model-importance) is that holding up progress on all other parts of the app while a big data model migration is ongoing is a recipe for no progress on anything.

So with that lesson in mind, we're pursuing a different strategy for this migration. We're going to take it in steps, where each step is small and can be deployed separately, while the rest of the application still works. First up with that in mind is syncing all of the existing ingredient and amount information from `ReagentAmount`s to `Recipe`s, and then keeping those things in sync as we go forward.

I got a head start on this way back in April with the addition of an `ingredients_blob` jsonb column on `Recipe`s ([migration for reference](https://github.com/edbrown23/barkeep/blob/master/db/migrate/20230328022702_add_ingredients_blob_to_recipes.rb)). I lazily update this column whenever a cocktail recipe is updated, meaning some of my recipes have their correct ingredient information, and others don't. Since it's time to lean into this project with this series of posts, it's also time to write the real migration that will hoist all ingredient information onto all recipes.

### Aside: To rake or not to rake, that is the question

At work, where I (or my team really, #management-life) work on rails apps, we have had the debate between data migrations such as this as one and one off rake tasks that accomplish the same thing. Clearly the results of those debates haven't stuck in my head, because in working on this project I've had the same debate internally. As I see it, the reasoning goes like this:

- Use a migration
	- Pros
		- this is a pretty one-off task, so a migration is best
		- when supporting multiple devs who need their local envs to keep working, a migration will be more likely to ensure they automatically update their local databases
	- Cons
		- Theoretically a migration should be reversible, and data migrations are hard to reverse because you need to know the state from before the migration, and you just destroyed that state doing the migration
- Use a rake task
	- Pros
		- Easy to control the rollout of a rake task, since you need to manually run it (this could be a con too, depending on your perspective)
		- Blast impact is potentially smaller since a rake task has some interactivity if something goes wrong
	- Cons
		- Counter to the migration-pro above, you would have to tell other devs to actually run the rake task to support their local machines. (for me, this isn't really a con, since this is a one man show)

I've opted for a rake task for now, but actually for entirely different reasons than above: I don't actually care about doing this in production until it's time to start using the new column for actual FE features. Most of this work will be entirely in the database until everything is working and I can safely cutover FE functionality.

## Back to work

With that decision sorted, the rake task itself is easy:

```ruby
desc 'Hoist ingredient info from ReagentAmounts to Recipes'
task hoist_reagent_amounts: [:environment] do
  user_id = ENV.fetch('user_id', nil)

  # Recipes with nil user_id's are "shared". A wrinkle for another post
  initial_scope = user_id.present? ? Recipe.for_user(User.find(user_id)) : Recipe.for_user(nil)

  # includes pre-loads all the reagent amount models, which is faster for rails
  initial_scope.includes(:reagent_amounts).in_batches do |recipes|
    recipes.each do |recipe|
      Recipe.transaction do
        recipe.clear_ingredients

		# convert_to_blob does basically what it says on the tin for reagent amounts
        recipe.reagent_amounts.each { |ra| recipe << ra.convert_to_blob }

        recipe.save!
        Rails.logger.info("Hoisted #{recipe.name}")
      end
    end
  end
end
```

After running the above, my prototypical cocktail, the Last Word, will have a new column which looks like this:

```json
[
  {
    "tags": [
      "green_chartreuse"
    ],
    "amount": "0.75",
    "unit": "oz",
    "reagent_amount_id": 17375
  },
  {
    "tags": [
      "gin",
      "london_dry_gin"
    ],
    "amount": "0.75",
    "unit": "oz",
    "reagent_amount_id": 17376
  },
  {
    "tags": [
      "luxardo_marascino"
    ],
    "amount": "0.75",
    "unit": "oz",
    "reagent_amount_id": 17377
  },
  {
    "tags": [
      "lime_juice"
    ],
    "amount": "0.75",
    "unit": "oz",
    "reagent_amount_id": 17378
  }
]
```

Why the `reagent_amount_id`'s? I'm not entirely sure they're necessary, but I had/have some ambitions about checking my work between my proven `ReagentAmount` based recipe determination and the new blob based model, and those links will allow me to do that. We'll see if I get to that, it all depends on how many parts I want this series to have...

Now, I'll admit this is all the same information that existed on its separate amount models. But that's intentional, we're working incrementally. With this "migration" done, and with my existing controllers already updating these ingredient blobs, my recipe's should stay in sync across edits.

## Next steps

Next time, we get into the fun stuff. Based on my experimentation a few months back, once the data is all living on the direct `Recipe` models I'll be able to build Postgres `ts_vector` column's off of them. These columns enable Postgres full text search, which I can then use for all of my querying. We shall see how successful I am, but as of today I'm feeling more excited than apprehensive, which is a good start. See you all next time!

<hr>

Last week's post: [Rails (and its ecosystem) is great](https://edbrown23.github.io/blog/2023/05/07/rails-ecosystem-is-great)

Next week's post: [Postgres Faceting - Part Two](https://edbrown23.github.io/blog/2023/06/04/postgres-faceting-part-two)

