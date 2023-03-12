---
title: "Is your front end running? Better go catch it"
date: 2023-03-12
---

Remember [last time](https://edbrown23.github.io/blog/2023/02/26/data-model-importance), when I wrote a long long post about the importance of getting your data model right? How having a data model that feels comfortable and cozy amplifies your creativity? And how, in an equal and opposite way, a poor data model hinders your ability to make any progress on your project?

This week I've realized the actual truth of that post: that rule applies to everything, but in my case, it especially applies to my Front End, which is unfortunately closer to the hindering side of that equation.

## Some Context

FE dev has never been my speciality. I've always considered myself "capable enough to be dangerous"; as in, I never entirely shy away from doing it, but do I use the best design patterns? Absolutely not. With that in mind, let's go over the not-so-great choices I've made in barkeep so far.

### First: rails views

Since barkeep is a rails app, the primary source for HTML is rails views. These are everything they've always been, and for that purposes I think they do a great job. ERB is a pleasant and straightforward, if mundane, templating language that lets you stay in the ruby headspace as you work, which is great for decreasing context-switching.

Rails views aren't as simple as they used to be, and they have lots of new tricks up their sleeves that are aimed at speeding up every day applications. More on this later, but I've avoided a lot of these tricks in my views. I use them to render HTML on the server, as god intended.

### Second: Bootstrap

I learned about Bootstrap back in college, and I think I've used it ever since for every side project that touches the web. I find it an intuitive framework for producing plain, but not ugly front ends. Basically, it gets the job done for me, and I'm a sucker for a `<NavBar>` and some modals. I've heard the new hotness is tailwind.css, but I'm so behind the times that my brain still thinks that's a [nutrition product](https://tailwindnutrition.com/), not a [css framework](https://tailwindcss.com/). Bootstrap is just opinionated enough, and gives me enough tools that I can start thinking about UX instead of `divs` and DOMs.

### Third: my custom JS

Bootstrap, plus those "capable enough to be dangerous" abilities, are pretty risk free on their own. Add a third ingredient like, say, Javascript, and that's when the cocktail starts to go off the rails. I figured out a system early on for defining per page js files which allows me to define dynamic UI functionality in some specific cases. The recent months of data-model-induced creativity have expanded my usage of these files, and now I have an app with what feels like a growing reliance on JS with no plan to actually organize that code.

For more contextual basics:
- It's all pure JS, but I bet I snuck jQuery in there somewhere by mistake
	- As an aside, browsers seem to shim jQuery nowadays by having a default `$` function, which messed me up for weeks. Nuts.
- I have no idea how to correctly include external JS libraries, so the ones I absolutely must have, like [`select2`](https://select2.org/), are vendor'd into my application 
- `turbolinks` is an unholy mess, because I don't lean into it. More on this later, but my per page javascript files mostly define hooks which are registered on `turbolinks:load`. 
	- For the non-rails devs in the audience, turbolinks portends to speed up page loads by executing all links via AJAX, then replacing the `<body>` of the page with the result, without reloading the `<head>`. This works great for that specific purpose, but means that `document.addEventListener("load")`-based callbacks will never work because the page actually never reloads.

## What's going wrong?

Most of my issues boil down to not knowing what to do with my javascript. Each file primarily registers page specific event hooks that want to either send requests based on user actions or respond to successful AJAX requests. These have to be page specific because they define specific handlers to generic events. For example, I frequently register handlers for `ajax:success`, which obviously fires all the time across my entire application. Every firing, however, is because of a specific user action and should be reflected in specific UI changes.

Exacerbating this problem, Rails provides no simple ways to actually manage page specific JS. There are [StackOverflow](https://stackoverflow.com/questions/59493803/using-rails-6-where-do-you-put-your-page-specific-javascript-code) posts, but I challenge any reader to tell me the "recommended" solution from those responses. And when reddit weighs in, it's to say that [page specific javascript is in and of itself a bad idea](https://www.reddit.com/r/rails/comments/imrqlk/comment/g42e4fy/?utm_source=share&utm_medium=web2x&context=3). But then how do I register my handlers to the right DOM elements??

All of this has resulted in tons of copied code in my javascript files (exactly what reddit predicted :cry:), which has been the source of endless bugs in my production app. I haven't exactly been following "best practices" with this project, as anyone who digs into my [spec folder](https://github.com/edbrown23/barkeep/tree/master/spec) would confirm. Full unit test coverage on the ruby side would never find [missing arguments](https://github.com/edbrown23/barkeep/commit/dbe70984d581b861dca1bb1430d1125b8d56debb) in my repeated JS code though.

New features are more than likely going to require more JS, so I need to come up with a solution.

## What are my paths out of this mess?

One solution would be to lean into Rails _even harder_. Rails 7 provides lots of tools for creating dynamic UIs, and technically a new Rails 7 application is a single page app by default. Most of my UI patterns would work with just Turbo, the successor to my use of Turbolinks. Even my most complicated modal could be done with [Stimulus](https://www.hotrails.dev/articles/rails-modals-with-hotwire).

So why not do this? A few reasons come to mind. First, leaning this hard into rails and its frameworks means this is pretty much always going to be a full rails app. Converting down the road to some other framework is going to be a full rewrite, which will almost certainly never happen. Second, Rails for me is the definition of a "Stockholm syndrome" framework. It takes time to get used to its patterns, and while you're doing it the documentation is awful so actually converting my app will be a pretty big challenge (and take a long time). Much like I mentioned in my data model post, if I decide to do this I'm committing to probably months of work (since I work pretty slowly) while no new features can safely added. Last, my app is Rails 6, and uses turbolinks, not turbo. Actually upgrading is not going to be easy.

I could also lean away from rails and try to convert the app to a "real" FE framework. I'm most familiar with React, so it'd probably be that, but maybe one of hot new frameworks out there would be better, like next.js.

What's stopping me here? Again, a few reasons. First, it's certainly a more significant deployment effort to own a react app + a rails app. I need something to serve the FE, I need a whole asset pipeline (or actually learn how rails does it), I need to duplicate this all locally for local dev, the list goes on. It's just more of a burden, and I'm trying to avoid burdens with this project. Second, I'll need to convert the backend of my app to be much more "API oriented". Rails doesn't make this terribly hard, but it'd still be a significant amount of rewriting.

My last realistic option, I think, is to just suck it up and try to organize my existing JS into modules, share more code between pages, and get by. This is the simplest solution, and honestly the one I'm most likely to follow for now. It also doesn't preclude me from doing one of the above options long term either, though the more I write now the less likely I am to do anything drastic down the road.

## The real real problem

All of this brings me to the realization of my real, actual problem. Programming is hard, and sometimes you have to either suck it up and do the hard work to make your future life easier, or suck it up now and just keep doing the "not perfect" thing so that you can keep adding features. Like I mentioned last week, I want a code base that inspires me, that never gets in the way of my UX, that encourages me to keep getting that [1% better](https://edbrown23.github.io/blog/2023/02/12/forever-better). I also want to actually improve the app, not spend weeks and months painstakingly converting pages to some new framework instead of improving the cocktail detail page or something. It's very difficult to balance those two things in a side project.

And there's one last challenge to add to all this; I'd love barkeep (or some other idea that comes to me down the road) to be a real app that someone pays me for someday. That means it'd be a business, and not a side project. Do I want to be running a business that doesn't have unit tests, and uses some Frankenstein's monster of a FE framework because I "know enough to be dangerous"? Would I want to work at such a place? Almost certainly not, but I also don't want to do any of those things now while it's a side project, since they'll slow me down.

So what's the answer? I'm not 100% sure, but I think I just need to keep practicing and getting better at being a scrappy independent developer. I think I'm recognizing myself in [the gap](https://youtu.be/91FQKciKfHI), and the only way out is forward. I need to keep trying things and hope that each new attempt makes it further than last time. Fingers crossed that we can keep it up.

<hr>

Last week's post: [Forever Better](/2023/02/26/data-model-importance).
