---
title: "Converting from turbolinks to turbo"
date: 2023-04-23
---

# Converting from turbolinks to turbo

As has been mentioned many times before, [barkeep](https://barkeep.website) is a rails app, and from a technology perspective it doesn't do anything particularly impressive yet. Still, for those with experience, rails carries with it a certain reputation for not being easy to upgrade, which I figured was a reputation that was also deserved for rail's "FE" frameworks, [turbolinks](https://github.com/turbolinks/turbolinks) and [turbo](https://github.com/hotwired/turbo-rails).

Given that, I had a big long post in mind this week covering just that: the pain of upgrading my app, simple though it might be, from turbolinks to turbo. However, I sit here writing this with shock written on my face (truly!), because this was the easiest migration ever! So much so my ambitions have expanded and this post will actually cover both the upgrade and converting one previously manual javascript component into "native turbo".

## First, what are these turbo things?

Rails is, by design, a server side rendering framework. That means all the fancy dynamic HTML rendering happens on the server for every request, and a big fat blob of HTML is sent to the client for every request. The rails devs, always on the lookout for a way to demonstrate their "convention over configuration" mindset, came up with a way to optimize this, and `turbolinks` was born.

Turbolinks is built on the realization that there's a lot of content in that full HTML blob which doesn't change, _especially_ all of the static content like CSS, JS, etc. It takes advantage of this realization by doing one simple trick; it intercepts every request you make to your server when you click on a link (the turbo*links* part), runs it via AJAX instead, and then replaces just the `<body>` tag with what is returned. (I wrote about how this impacts me in [My Front End is Bad News](2023/03/12/my-frontend-is-bad))

Turbo takes this a step further by also applying its AJAX trick to form submissions, hence dropping the "links" from the end of the name.

Now, in actuality, `turbo` is a host of several features which are aimed at making it possible to write single page web apps without ever writing Javascript, which in general is something I can get behind. Plus, no Javascript means maybe my front end is less bad news. Let's see if that pans out...

## Doing the upgrade

I've hesitated doing this upgrade for over a month because I just assumed it'd be miserable. Convention over configuration is great when you're on the happy path, but the moment you're not, for whatever reason, you're usually trapped in a terrible quagmire of inscrutable error messages and sadness.

However, this week I just decided to dive in, and in doing so I rapidly found the official upgrade guidance for moving from turbolinks -> turbo: [UPGRADING.md](https://github.com/hotwired/turbo-rails/blob/main/UPGRADING.md#upgrading-from-rails-ujs--turbolinks-to-turbo). These five (four for me, since no mobile) steps seemed pretty straightforward, so I just did them one by one and committed the whole bunch, as you can see in the diff [here](https://github.com/edbrown23/barkeep/commit/cb4a2338e6e0c59007c0515f3b18a115a8da6c26).

I was really expecting to have to debug _something_, but I kid you not I made the changes above, restarted my local rails server, and everything worked immediately! Amazing. Do I think this was due to any greatness on my part? Absolutely not! `barkeep` is just so dang simple there isn't much that can go wrong.

Now, I obviously can't leave it at that. I wanted to write about my experiences upgrading to _and_ using `turbo`, so let's just skip right to the using part!

## Using turbo

When I say "using turbo", what I really mean at least initially is using turbo frames. These frames allow you to tag parts of your views, and then turbo frames will intelligently slot the tagged content from one view into another view with minimal overhead or coordination.

Someone not invested in a rails app would probably read the above in horror (looking at you Quinten). Part of me absolutely agrees, this is convention over configuration to the nth degree, with tags in one view needing to line up perfectly with tags in another view all so turbo can save you a bit of page loading time. (and actually it gets worse, if you can believe it. Turbo Streams do all of the above but in real time over a websocket 😱).

Still, there are some advantages that I can think up for me. First of all, as you're doing all this frame tagging you're still writing the original HTML views, which means they are already done and will naturally be kept up to date. This means that my app should still work normally, albeit with a slightly worse UX, on a client with Javascript disabled since we'll just fall back to regular link navigation behavior.

Second, as covered in my oft-referenced FE post, my front end is already a disaster. It's too late realistically to convert everything to a react app, and my custom JS is busting at the seams. The only responsible thing to do is to lean into rails, the [one person framework](https://world.hey.com/dhh/the-one-person-framework-711e6318).

## Enough talk, do some work why don't you!

Sir, yes sir!

The app is converted to turbo, so all that's left is to pick out which functionality should utilize turbo frames. First, I need to find some quality documentation for how all this turbo frames business works. Thankfully, some generous community member has written an extensive series of tutorials on the topic which we'll be following: https://www.hotrails.dev/turbo-rails/.

I'm going to target the home page for the first use of turbo (and stimulus, most likely). It's due for a redesign, but for now the home page highlights which drinks you have the ingredients for right now. In doing so it renders on the server side all of the ingredients for all of the drinks, which can end up being a lot of data if you have the ingredients for a lot of drinks.

![original_home_page](/blog/docs/assets/2023-04-23/original_home_page.gif)
*Each expanded cocktail section is sent over in the original HTML, which can be pretty heavy*

Each of those cocktail sections is a separate table, rendered via rails views as shown:
```html
<div class="collapse" id="ingredients_<%= cocktail.id %>">
  <table class="table">
    <thead>
      <tr>
        <th>Ingredient</th>
        <th>Required Volume</th>
      </tr>
    </thead>
    <tbody>
      <% cocktail.reagent_amounts.each do |reagent_amount| %>
        <tr>
          <td>
            <samp>
              <% reagent_amount.tags.each_with_index do |tag, i| %>
                <%= link_to tag, reagent_category_path(tag) %><% if i != reagent_amount.tags.size - 1 %><span>, </span><% end %>
              <% end %>
            </samp>
          </td>
          <td><%= "#{reagent_amount.amount} #{reagent_amount.unit}" %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <button data-cocktail-id=<%= cocktail.id %> data-pre-route="/cocktails" class="btn btn-primary made-this-button">Make Drink</button>
</div>
```

The turbo-frames realization here is that the per cocktail tables above are very similar to the ingredients table on the cocktail "show" page, so I can probably re-use them. The cherry-on-top? Using turbo-frames will make individual requests per cocktail, lazy-loading the ingredients as needed and reducing the overall size of the initial home page HTML.

![cocktail_show](/blog/docs/assets/2023-04-23/cocktail_show.png)
*The table on the cocktail show page. Basically the same as the home page table*

In order to use turbo-frames here, I need to tag the table I'm going to re-use with a `turbo_frame_tag` that is unique to each cocktail, then add the same tag to the home page where the table will slot in.

So, with frames the above HTML becomes:
```html
<%= turbo_frame_tag(cocktail) do %>
<% end %>
<button data-cocktail-id=<%= cocktail.id %> data-pre-route="/cocktails" class="btn btn-primary made-this-button">Make Drink</button>
```
*Much simpler, right?*

This frame requires a request to fill it in, which is done via a `link` and a special data attribute:
```html
<td><%= link_to 'Show Ingredients', cocktail_path(cocktail), class: "btn btn-outline-info", data: { turbo_frame: dom_id(cocktail) } %>
```

Lastly, I need to add the same tag to the table that's being reused:
```html
<%= turbo_frame_tag(@cocktail) do %>
<div class="table-responsive">
...
<% end %>	
```
*Most details of this section elided, but it's a bunch of table html*

That's it! (ish, as we'll see).

The home page now does this:
![first_turbo_version](/blog/docs/assets/2023-04-23/first_turbo_version.gif)
*Not quite right...*

We're now correctly lazily loading the ingredients table, which is great. However, we've lost the "collapse" behavior we had before, and the "Make Drink" button is showing up when it shouldn't. Turns out, we need another new rails tool to make this work: Stimulus.

## Get Stimulated

[Stimulus](https://stimulus.hotwired.dev/) is a javascript framework that is meant to complement all of the existing turbo tools to give you just enough javascript to make your application shine, without becoming encumbered by it. Sounds like just what my FE needs, right?

How does it help me here? It handles showing and hiding the collapse element on demand! Let's get down to business.

First, we add `stimulus-rails` to our Gemfile, `bundle install`, then `rails stimulus:install`. My Front End, in it's infinite generosity, confuses things a little bit here since I use an `app/frontend/packs` directory instead of `app/javascript`, but an additional import of `import ../../javascript/controllers` gets everything in working order.

Next up, we use the rails generator to create my Stimulus Controller. I'm betting in a few weeks I'll be writing much better controllers, but for now, the following simple file is all I need:
```js
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="home-index"
export default class extends Controller {
  static get targets() {
    return [ "collapse" ]
  }

  connect() {
  }

  toggleCollapse() {
    let collapse = new bootstrap.Collapse(this.collapseTarget);
    collapse.toggle();
  }
}
```

To trigger this functionality, I have to call this controller via my HTML:

```html
<tr data-controller="home-index">
  <td><%= link_to cocktail.name.html_safe, cocktail_path(cocktail) %></td>
  <td>
    <%=
      link_to 'Show Ingredients',
        cocktail_path(cocktail),
        class: "btn btn-outline-info", 
        data: { 
          turbo_frame: dom_id(cocktail)
          action: "click->home-index#toggleCollapse"
        }
    %>
  </td>
  <td>
    <div class="collapse" data-home-index-target="collapse">
      <%= turbo_frame_tag(cocktail) do %>
        <p>Loading...</p>
      <% end %>
      <button data-cocktail-id=<%= cocktail.id %> data-pre-route="/cocktails" class="btn btn-primary made-this-button">Make Drink</button>
    </div>
  </td>
</tr>
```

The key change here is the addition of the `data-*` attributes in the `<tr>` element. `data-controller="home-index"` tells Stimulus what controller to use, and the `data-action` attribute on the `link_to` tells it what method to call and when. The final key connection is `data-home-index-target="collapse"`, which allows the controller to easily find the bootstrap element that needs to be toggled.

That's it!

![working_stimulus](/blog/docs/assets/2023-04-23/working_stimulus.gif)
*I bet I can refine the loading screen behavior, but most importantly, it works!*

## What's next?

What I've done here is only the beginning. I still have lots of javascript that needs to be reworked as Stimulus Controllers, many more links that I can re-use as turbo-frames, the list goes on. I am a little afraid of being _so_ reliant on rails, but there's also some comfort in being able to lean into the framework to do the thinking for me. We'll see if I regret it!

<hr>

Last week's post: [Converting to Docker in Digital Ocean](https://edbrown23.github.io/blog/2023/04/10/converting-to-docker)