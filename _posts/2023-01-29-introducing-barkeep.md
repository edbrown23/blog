---
title: "Introducing Barkeep"
date: 2023-01-29
---

# An Intro

At the beginning of the pandemic, during those feverish months of March and April 2020, I got really into making cocktails. As I'm sure it was for many others, the early periods of lockdown were simultaneously stressful and boring, and having drinks with my roommates was a welcome way to relax after yet another day of the "new normal". However, I could only have so many Manhattans and Boulevardiers (both still favorites today!) before I felt the need to branch out.

Enter [tuxedono2](https://tuxedono2.com/), an amazing cocktail resource with a few gateway features that enabled my search for a fuller cocktail experience:
- A "Similar To" section at the bottom of each recipe, with links to other drinks I might be able to make
- A delightfully simple "Ingredients" index, where each ingredient links to all the drinks you can make with a specific bottle

Those two elements were all I needed to scamper off to the local liquor store on a near weekly basis looking for a new bottle that would unlock yet another new cocktail. If I bought Absinthe, I could make a Corpse Reviver #2 _and_ a Sazerac! Or, Benedictine, which adds delightful richness to spirit forward cocktails, could unlock classics like the Vieux Carre or my absolute favorite, the Cock N' Bull. 

However, I soon found myself with a new problem: a growing collection of diverse liquors and the same Manhattan still being all I make when the night calls for a drink. I learned I needed more than just a superb list of cocktail recipes, but also some help knowing what my current collection could actually make, now, today.

That led me, finally, to the conclusion I've reached countless times before but never acted on with much conviction: "I could write code to do this!". What I had before me was a simple set problem, where an intersection writ large between my bottles and all the cocktail recipes I can store in a Postgres database would tell me exactly what I can make at any time, instantly. That goal has turned into [barkeep](https://barkeep.website), a SaaS bartender which aims to help you (well, me really) keep track of our home bars and utilize them to the best of their abilities.

## The Technical Stuff

Barkeep is [open source](https://github.com/edbrown23/barkeep), built with Ruby on Rails and Twitter Bootstrap. Expect many future blog posts on my thoughts and feelings on those frameworks, both positive and negative. As of today, it's a pretty simple CRUD application, but one that scratches a very particular and charming itch for me. I don't believe it yet does anything technically "impressive", but it solves a real problem for me, and I think that is ultimately what counts. 

I'm already working on a future post about data models and how essential they are to these projects, so as a preview of that content: `barkeep` stores all of its recipes, and the relationships between those recipes and the bottles that fulfill them, in several Postgres tables. In the interest of cost savings while hosting, I've erred on the side of doing everything I can in Postgres, instead of reaching for an additional data storage system like Redis or ElasticSearch. Constraints breed creativity, however, and I'm already exploring ways to utilize some of the more esoteric Postgres features like full text search. I'm breaking the record as we speak by saying this, but expect future posts on that too!

Last but not least, I'm obsessed with the idea of lifestyle businesses, and would love to have barkeep, or some descendent of it, become a business for me. I believe that software's original ability to scale productivity with minimal resources has too often been clouded by the world of Venture Capital and Growth Hacking and Making it up in Volume, but I also believe in the basic economics of [1000 true fans](https://kk.org/thetechnium/1000-true-fans/). I think that regular people have everyday problems that can be solved, delightfully, with software tools, and that someone (hopefully me) can make a living doing so, without needing to change the world or create a pitch deck or grow at all costs. It's naive to think my first project will accomplish that goal, but I can't have a successful second (or tenth) project without the first one.