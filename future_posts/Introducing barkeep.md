## An Intro

At the beginning of the pandemic, during those feverish months of March and April 2020, I got really into making cocktails. As I'm sure it was for many others, the early periods of lockdown were simultaneously stressful and boring, and having drinks with my roommates was a welcome way to relax after yet another day of the "new normal". However, I could only have so many Manhattans and Boulevardiers (both still favorites today!) before I felt the need to branch out.

Enter [tuxedono2](https://tuxedono2.com/), an amazing cocktail resource which had a few gateway features that enabled my search for a fuller cocktail experience:
- A "Similar To" section at the bottom of each recipe, with links to other drinks I might be able to make
- A delightfully simple "Ingredients" index, where each ingredient links to all the drinks you can make with a specific bottle

Those two elements were all I needed to scamper off to the local liquor store (or the ingredient super store of the Northeast, Total Wine) on a near weekly basis looking for a new bottle that would unlock yet another new cocktail. If I bought Absinthe, I could make a Corpse Reviver #2 _and_ a Sazerac! Or, Benedictine, the best friend to anyone who prefers spirit forward cocktails, which unlocks innumerable classics like the Vieux Carre or my absolute favorite, the Cock N' Bull. 

However, I soon found myself with a new problem: a growing collection of diverse liquors and the same Manhattan still being all I make when the night calls for a drink. I learned I needed more than just a superb list of cocktail recipes, but also some help knowing what my current collection could actually make, now, today.

That led me, finally, to the conclusion I've reached countless times before but never acted on with much conviction: "I could write code to do this!". What I had before me was a simple set problem, where an intersection writ large between my bottles and all the cocktail recipes I can store in a Postgres database would tell me exactly what I can make at any time, instantly. That goal has turned into [barkeep](https://barkeep.website), a SaaS bartender which aims to help you (well, me really) keep track of our home bars and utilize them to the best of their abilities.

## The Technical Stuff

Barkeep is [open source](https://github.com/edbrown23/barkeep), built with Ruby on Rails and Twitter Bootstrap. Expect many future blog posts on my thoughts on feelings on those frameworks, both positive and negative. As of today, it's a pretty simple CRUD application, but one that scratches a very particular and charming itch for me. Perhaps this veers too far into self-deprecation, but I don't believe it yet does anything technically "impressive". Despite that, I'm a firm believer that solving real user problems is what matters, and I know at least one user who desperately needs this.

