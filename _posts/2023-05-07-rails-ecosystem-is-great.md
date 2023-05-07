---
title: "Rails (and its ecosystem) is great"
date: 2023-05-07
---

# Rails (and its ecosystem) is great

In my senior year of college, we had a few capstone courses that were supposed to round out the computer science and computer engineering majors with some end to end project experience. In both courses I ended up mostly focusing on web apps, but only one course gave me the choice of which framework to use (I chose [django](https://www.djangoproject.com/)). In the other class, I was required to use [ruby on rails](https://rubyonrails.org/).

Some 10 years on, I have little recollection of the actual project I built in that senior year course. What I do remember is my extreme distaste for Rails. Everything about it rubbed me the wrong way, and while I got the project across the finish line I swore off ever using rails again. All I could see were the negative effects of rails' fundamental design decision, "convention over configuration". But Eric, I hear you say, what's up with the title of this post!?

Well, it turns out I pre-judged rails a bit back then. After 6 years of working primarily in ruby and rails at my work, I've come around almost completely. And clearly I've come around enough to write `barkeep` in rails. So what triggered that reversal? For the most part, it was the rails ecosystem that did the trick.

## What makes an ecosystem?

A bare rails app gives you quite a lot up front, but this is the year 2023, and quite a lot hardly cuts it anymore. Any modern day application needs user authentication, pagination, admin pages, etc. What establishes rails's ecosystem credentials is the vast number of high quality gems that solve all of those problems with minimal effort. How minimal? Let's see...

### User Authentication

As referenced in [my data model post](2023/02/26/data-model-importance), I added users to barkeep once I decided to host it on the public internet. That meant I needed auth, and so entered [devise](https://github.com/heartcombo/devise).  `devise` makes setting up a user flow incredibly easy. For me, all I had to do was install the gem, run the basic generators, add `before_action :authenticate_user!` to my controllers, and I had working auth. The gem packages basic login views, so to start out I didn't have to write a single line of HTML, and once I did want to customize the views to bootstrap-ify everything I could run one other generator and all the files I needed were created and slotted in automatically.

Of all the tools listed in this post, `devise` is the one I've reached into the least, but I rely on it all over my app and it's routinely easy to use. 

### Admin Pages

With my app on the internet, I started to invest in functionality that would allow me to administrate the important pieces of data without using `rails console` or making direct database changes. This was accomplished originally with the addition of user roles (made easy by devise, yet again), but I needed to reflect my "admin" role with special views in the app itself.

At first, I implemented these special views by just appending additional HTML to my view whenever `current_user.admin?` was true (`current_user` being a tool provided by devise to access the currently logged in user from any controller or view). This worked, but it meant that my views were starting to be polluted with these special cases, and writing individual admin experiences was a pain. Eventually I realized the rails ecosystem has to have a solution to this, and at that point I discovered [administrate](https://github.com/thoughtbot/administrate).

`administrate`, like `devise`, is trivial to setup, and its defaults immediately give you a workable solution. I added one additional gem, [administrate-field-jsonb](https://github.com/codica2/administrate-field-jsonb) (another ecosystem win!), and immediately I had an admin view with the ability to render and modify any of my models, including a rich JSON editor!

SCREENSHOT HERE!!

### Pagination

Last but not least, over this past weekend I was visiting NYC, which meant I had a few hours to kill on the train. I decided that was the perfect time to add pagination to my cocktail views, since my recipe count of over 200 cocktails was starting to be unwieldy. How hard could it be? Well, armed with that rails ecosystem again, it was so easy I had to find other parts of the project to work on with all my extra time!

This time it was the [kaminari](https://github.com/kaminari/kaminari) gem providing the tools. I approached this gem with some trepidation, since I had gone in expecting to use [will_paginate](https://github.com/mislav/will_paginate), but I learned quickly that that gem has been deprecated. However, I had nothing to fear, because `kaminari` is awesome!

With the gem installed, there was _literally_ nothing else I had to do to get basic pagination working. `Recipe.page(3)` immediately worked by default, returning me the third page of results, with 25 entries per page. And since this pagination is done via scopes, it automatically worked with my other chaining scopes, like my `for_user` scope which knows how to return only the current user's models.

Naturally I needed some way for the user to select their pages, but `kaminari` has this solved too. All you need to do is add the following to any view, and the correct links are generated with appropriate numbers of pages and the right `page` params setup in each link:

```erb
<%= paginate @cocktails %>
```

Now, I needed to style these buttons as bootstrap pagination links, so they look their best. This was also trivial though, because `kaminari` ships with a series of themes, available at [kaminari_themes](https://github.com/amatsuda/kaminari_themes). A simple `rails generate kaminari:views bootstrap4` invocation later, and my pagination links were automatically themed for me as well! This entire "project" required [51 additions and 6 deletions](https://github.com/edbrown23/barkeep/commit/f37d5bade4fae6034e618e27bdc63c955bb8f358), and the vast majority of those additions were auto-generated views.

## So what's the downside?

Obviously I'm pretty glowing about the rails ecosystem here, and for good reason. But it's not all sunshine and roses. Rails is the Apple of web frameworks, meaning when you're inside the walled garden life is amazing and perfect, but if you dare step outside it things get treacherous in a hurry. All of the gems listed here were only able to apply their full magic _because_ barkeep is a simple, run of the mill rails app. If I was rolling my own FE, I'd not have benefited from most of these tools because I wouldn't be able to rely on the automatically included views that each gem provides.

Thankfully, for me, I've decided to go all in on rails for this project. The benefits of "[conceptual compression](https://medium.com/signal-v-noise/threes-company-df77db78d1af)" found by leaning into these tools allows me to keep making progress on `barkeep` even when I take a week off, or only have an hour here or there. So for now, the sun is shining and the flowers are blooming in the rails ecosystem for me.

<hr>

Last week's post: [Converting from turbolinks to turbo](https://edbrown23.github.io/blog/2023/04/23/converting-from-turbolinks-to-turbo)

