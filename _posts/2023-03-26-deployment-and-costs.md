---
title: "Deploying Barkeep"
date: 2023-03-26
---

# Deploying Barkeep

When I started `barkeep`, my intention was to host the entire application locally on a NUC that I've had since 2017, and used for essentially nothing. It was going to be a very personal side project, so why bother with hosting? As feature started to develop, I realized I wanted to take `barkeep` on the go, letting it keep track of shopping lists on my phone and a future "remote bartender" mode when I'm at other people's houses. Remote access, at the time, meant deploying it on the internet, and that meant I needed hosting.

(side note: I wish I had known about [tailscale](LINK ME) at the time, cause I might have just gone that route and still NUC hosted if I had. There's something super cool about the idea of tailscale'ing to my home server to access my liquor cabinet app which goes untapped with my current deployment)

Today, [barkeep](https://barkeep.website) is deployed on Digital Ocean's [app platform](https://www.digitalocean.com/products/app-platform), which can best be described as one of the many Platform-as-a-Service heirs to the heroku throne. It doesn't have an absolutely free tier for non-static sites, but all things considered I think that's a good business decision for them, as recognized by this [hacker news thread](https://news.ycombinator.com/item?id=35044516) on another heroku-like, fly.io. Digital Ocean provides me with a small but manageable Postgres instance for $7 a month, plus roughly $5 a month in app deployments, which adds up to a respectable $12 a month to maintain barkeep as it stands today.

Now, I can pretty safely lose $12 a month on barkeep forever, but if I am ever lucky enough to be graced with real users, hosting and infrastructure costs are going to start adding up quickly. Here's some basic thinking:
- A managed Postgres instance on DO costs a minimum of $15 a month, and if I want a failover that _quadruples_ the total price to $60 a month, at $30 for each instance. 
	- These are pretty small databases too! $30 a month only gives me 2GB of RAM, 1 vCPU, and 25GB of disc. Probably enough for awhile, but pretty paltry
- Horizontally scaling my actual app is going to add up fast, as my $5 a month nodes only give me 512MB of RAM (remember this is a rails app 😱) and 1 vCPU. Two nodes, $10 a month. 1GB of RAM? $10 a month each, or $20 for two nodes. Expensive.

I can defray the costs of deployment a little longer if I ditch the App Platform, which is a pretty safe bet. Individual Droplets on DO are more than likely more cost efficient, since I can get a single droplet with 8GB of memory and 4 CPUs for $56 a month. I'd probably want two for redundancy, but the cost per GB of memory still works out to $7 per GB per month via that Droplet, vs $10 per GB per month from my previous example.

If I do this, however, my other costs add up, as does the relative complexity of my deployment. I'll need to add a load balancer if I have two nodes, and that carries some cost (cost which is priced into the App Platform I believe). And on the complexity point, I'll need to come up with an actual plan for "professional-izing" my devops skills. Since I'm already going deeper into the rails ecosystem, maybe I lean into 37signals new deployment tool as well, [mrsk](https://github.com/mrsked/mrsk).

On top of all this are secondary costs which are unavoidable down the road. If I ever have multiple app nodes I will likely need a log aggregator, which means paying for that too. Likewise some sort of APM platform is a necessity, especially because while I've gone to not insignificant lengths to avoid N+1 queries in barkeep so far, I've completely ignored indexes so far. Debugging a poorly performing rails app _without_ these tools seems like an exercise in futility, so that's one more cost I'll need to eat.

## The math of a lifestyle business

I'm getting ahead of myself calling any of this a business, but it feels appropriate to at least be thinking about it ahead of time. In an ideal world, a slow but growing trickle of cocktail enthusiasts will someday find barkeep a compelling enough product to fork over, say, $5 a month, for its services. I won't be able to survive on the cheap tier of the App Platform for long, which means I'm going to be doing some basic algebra pretty soon to understand my run rate.

Without doing any math at all, my intuition says that for the first ~10 customers, my costs will outpace my revenue. My minuscule database will need to go first, and that adds $53 a month immediately (that's 10 customers right there!). I can hopefully ride on that database for awhile, but my web tier is next, and I'd better be able to find some efficiencies at that level while I'm on the App Platform because each node I add costs a minimum of one customer per month to pay back. And as mentioned previously, if I have multiple nodes I'm looking at probably $50 a month for aggregated logging just so I can debug issues across my nodes.

Already this is getting complicated, but honestly I wish more than anything to have these problems one day. The real joy in someday running a business like this, for me, is getting to be involved in every aspect of these decisions. I might love programming for the creative outlet it gives me, but I also love to learn. Everything I've just described sounds like a crash course in business accounting + technology. How cool is that?? Not to mention the real accounting that will have to happen if I ever manage to turn a profit. And that's just the money stuff.

Running a lifestyle business sounds, to me, like an opportunity to never stop learning, and to never find yourself in a complete rut. Even if your product is the niche-iest there ever was, the skills you need to apply to manage that business will be both broad and deep. The tech companies that so many of us call jobs today have a lot of good (and bad) qualities, but what they can never provide is a deep understanding of everything that is going on inside them. Nor should they; their value is in specialization and trust and distributed decision making assuming they're well run companies. No matter what, they'll never be able to provide the crash course in business fundamentals like truly finding yourself in the deep end of the shark tank of a lifestyle business seems to offer.

## What's next?

As with many of my posts, I've ended things on a whimsical note. Unlike those other times, however, I'd like to provide a tactical list of where things are going from here. So, from a deployment and business perspective, here's my plan:
- We're sticking with the DO App Platform for now. It gets the job done, and it lets me focus on the app itself, which needs work
- I should be using the Dockerfile based version of the App Platform so that I have more control over my dependencies instead of relying on the poorly documented [buildpacks](https://docs.digitalocean.com/products/app-platform/reference/buildpacks/ruby/) that are otherwise used. This will happen next, most likely.
- I'm starting to value the data in my database, and I want to invest in improving it even more by dramatically expanding my list of cocktail recipes. I _really_ won't want to lose this data, which means upgrading to a managed Postgres that I can get regular snapshots of.
	- Yes, this will increase my costs. Maybe it'll be time to actually send this app out there soon...
- Hopefully, I have a path to customers at this point, while also keeping my costs low. I've heard before that so many people give up on their apps before they get real usage. If I keep my run rate low, I only need to justify the existence of this app to its most important user, me, and I can keep it going forever in the search of actual paying usage.
- Customers will equal real challenge, so at that point it will be prudent to break out the spreadsheets, calculate my actual cost options, and then pursue a proper deployment solution. I may never reach this, but that's ok! Or, I'll try this as an exercise in learning about the devops side of the house and eat the cost
- If truly nothing ever seems like it'll work out, then it's back to [tailscale](https://tailscale.com/). I can always deploy barkeep to a local machine at home and access it remotely via VPN, and reduce my costs to only electricity. There's some excitement in that option too!

<hr>

Last week's post: [My Frontend is Bad](https://edbrown23.github.io/blog/2023/03/12/my-frontend-is-bad)

Next week's post: [Converting to Dockerfiles in Digital Ocean](https://edbrown23.github.io/blog/2023/04/10/converting-to-docker)