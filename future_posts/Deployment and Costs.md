---
title: "Deploying Barkeep"
date: 2023-03-12
---

When I started `barkeep`, my intention was to host the entire application locally on a NUC that I've had since 2017, and used for essentially nothing. It was going to be a very personal side project, so why bother with hosting? However, I soon realized I wanted to take `barkeep` on the go, letting it keep track of shopping lists on my phone and a future "remote bartender" mode when I'm at other people's houses. Remote access, at the time, meant deploying it on the internet, and that meant I needed hosting.

(side note: I kinda wish I had known about [tailscale](LINK ME) at the time, cause I might have just gone that route and still NUC hosted if I had. There's something super cool about the idea of tailscale'ing to my home server to access my liquor cabinet app which goes untapped with my current deployment)

Today, [barkeep](https://barkeep.website) is deployed on Digital Ocean's [app platform](LINK ME DADDY).