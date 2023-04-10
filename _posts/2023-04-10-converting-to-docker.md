---
title: "Converting to Docker in Digital Ocean - Live Blog Edition"
date: 2023-04-10
---

# Converting to Docker in Digital Ocean's App Platform

This week's post is a different style, largely because I woke up on Sunday (the day posts are due) with literally nothing written. It happens to the best of us. Our subject today is converting my existing `barkeep` application from Heroku-style buildpacks on Digital Ocean's App Platform to a Docker-based deployment.

I want to do this because I want to be moving a tiny bit closer to deploying my app on my own k8s cluster, and building with Docker is table stakes for that goal. Plus I've used plenty of Docker over the years in my career, so this should be relatively straightforward.

As to the style of this post, we're going with as true of a stream of consciousness as I can make it. Y'all are getting the real, lived experience of myself taking a part of my day off to do this small project.

## Step one: I need a Dockerfile

The time is 10:44 am Eastern Time, and I've decided to take on this project. Docker is easy, we deploy rails apps via Docker at work, etc etc. The first thing I need is the Dockerfile itself. Time for some googling.

10:50am: Found https://fly.io/ruby-dispatch/rails-on-docker/, seems like a pretty good starting point. Interestingly enough Rails is going to package a Dockerfile with every repo starting in version 7.1, but we're only on Rails 7.0 (And 7.1 isn't released yet, obv). Still, the post implies I can probably still use the same concepts, and the Dockerfile itself seems pretty straightforward. Let's try it.

10:53am: Already, a problem with the blog post. I add the `dockerfile-rails` gem as they suggest, but they say you can generate the Dockerfile itself with _just_ `rails dockerfile`. Rails obviously complains about that not being a command, but I know enough about rails to assume they meant to include "generate" in there (as one does when pulling in migrations from a gem), so we try `rails generate dockerfile` and...

```
ebrown ~/s/barkeep (master) (k8s-prod) $ bundle exec rails generate dockerfile
      create  Dockerfile
      create  .dockerignore
      create  .node-version
      create  bin/docker-entrypoint
```

Success!

Inspecting the generated file, it's pretty different from the one described in the blog post. Mine looks like this:

```
# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=2.7.2
FROM ruby:$RUBY_VERSION-slim as base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT="1"

# Update gems and bundler
RUN gem update --system --no-document && \
    gem install -N bundler


# Throw-away build stage to reduce size of final image
FROM base as build

# Install packages needed to build gems and node modules
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential curl git libpq-dev node-gyp pkg-config python

# Install JavaScript dependencies
ARG NODE_VERSION=12.22.11
ARG YARN_VERSION=1.22.18
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    npm install -g yarn@$YARN_VERSION && \
    rm -rf /tmp/node-build-master

# Install application gems
COPY --link Gemfile Gemfile.lock ./
RUN bundle install && \
    bundle exec bootsnap precompile --gemfile && \
    rm -rf ~/.bundle/ $BUNDLE_PATH/ruby/*/cache $BUNDLE_PATH/ruby/*/bundler/gems/*/.git

# Install node modules
COPY --link package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy application code
COPY --link . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE=DUMMY ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Run and own the application files as a non-root user for security
RUN useradd rails --home /rails --shell /bin/bash
USER rails:rails

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /rails /rails

# Deployment options
ENV RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="true"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
```

This is actually _better_ than I was expecting, because it did some nice things for me during generation. First, it autodetected my ruby version (which I need to update :rip:), and it brought in the Postgres libs. Pretty slick. Time to see if it works.

I know enough about Docker to know this part of the process might be slow, especially since it's the first build. Time to run `docker build . -t barkeep` and go move my sprinklers.

11:06am: back inside, and the build succeeded! Let's see if it works. First, google to remember the specific flags to use to run the image (turns out no flags are necessary).

```
ebrown ~/s/barkeep (master) (k8s-prod) $ docker run barkeep
rails aborted!
ArgumentError: Missing `secret_key_base` for 'production' environment, set this string with `bin/rails credentials:edit`
# more stack trace elided
```

Hmm, this looks somewhat familiar. Reviewing the help text from `bundle exec rails credentials:help` is, obviously, helpful, and I remember setting the `RAILS_MASTER_KEY` in DO's encrypted env vars. I _think_ what I'm seeing here isn't really an error, and is actually just the usual confusion of trying to run a rails application in production mode on your local machine. It almost never works the way you expect.

With that in mind, I think it might just be time to see how to tell DO to use my Dockerfile instead of the buildpack.

## Step two: Digital Ocean

11:23am: it feels like we're making progress. Digital Ocean's documentation is never great exactly, but this post seems to tell me everything I need: https://docs.digitalocean.com/products/app-platform/reference/dockerfile/.

The "App Spec" portion of the app platform is a bit touchy to me. It looks like code since it's a YAML file, so I want to manage it like code. However, it includes unencrypted database credentials as plaintext, so I really _don't_ want to manage it as code either. In this instance I guess I'll modify the file directly on DO.

I have two kinds of things deployed on DO currently: first, the app itself, which is a "service". Second, a "job", which runs post-deploy, that runs database migrations. Is it a good idea to separate my migrations from the code deploy? Probably not, but so far it's been working for me, and I have the job configured to only run if the code itself successfully deploys. For this project that means I need to update both with a `dockerfile_path: Dockerfile` directive.

11:28am: Upon updating both sections of my app spec and trying to save, I'm told that my existing `build_command` directive is in conflict with specifying a Dockerfile. My build command is saved in `bin/production-deploy.sh`, so lets see what it does:

```
# #!/usr/bin/env bash

# set -e
# set -x

# bundle install

# bundle exec rake db:prepare
```

Oh. I guess I can remove that then...

11:31am: `build_command` is gone, but we're not out of the woods yet. `environment_slug` also conflicts, which makes sense because that defines the heroku-esque buildpack. Let's try removing that too.

DO allows me to save the app spec, which immediately starts a deploy. Now is about the time I wish I had saved the old app spec first. Oh well.

11:33am: the build fails, which is always a sinking feeling, until you realize you're an idiot when you read the build failure:

```
[2023-04-10 15:32:54] ╭──────────── git repo clone ───────────╼
[2023-04-10 15:32:54] │  › fetching app source code
[2023-04-10 15:32:54] │ => Selecting branch "master"
[2023-04-10 15:32:55] │ => Checking out commit "9f6f749f962c2d88e2508d7ebdc24dd780170185"
[2023-04-10 15:32:55] │ 
[2023-04-10 15:32:55] │  ✔ cloned repo to /.app_platform_workspace
[2023-04-10 15:32:55] ╰────────────────────────────────────────╼
[2023-04-10 15:32:55] 
[2023-04-10 15:32:55]  › using dockerfile path Dockerfile
[2023-04-10 15:32:55]  ✘ no such file exists in the git repository.
```

Of course, of course. Time to commit the Dockerfile and push it up. Rails has generated a host of files, some of which I don't quite understand (especially the `.yarn/` directory). Still, we power forward and push everything, then start the DO deploy again.

11:38am: another failure, but this one seemingly less obvious:

```
[2023-04-10 15:38:22] ╭──────────── git repo clone ───────────╼
[2023-04-10 15:38:22] │  › fetching app source code
[2023-04-10 15:38:22] │ => Selecting branch "master"
[2023-04-10 15:38:22] │ => Checking out commit "57fff5a2d169e0642c588957aed7cb004bcd13dd"
[2023-04-10 15:38:22] │ 
[2023-04-10 15:38:22] │  ✔ cloned repo to /.app_platform_workspace
[2023-04-10 15:38:22] ╰────────────────────────────────────────╼
[2023-04-10 15:38:22] 
[2023-04-10 15:38:25]  › configuring build-time app environment variables:
[2023-04-10 15:38:25]      RAILS_MASTER_KEY RAILS_ENV
[2023-04-10 15:38:25] ╭──────────── dockerfile build ───────────╼
[2023-04-10 15:38:25] │  › using dockerfile /.app_platform_workspace/Dockerfile
[2023-04-10 15:38:25] │  › using build context /.app_platform_workspace//
[2023-04-10 15:38:25] │ 
[2023-04-10 15:38:26] │ error building image: parsing dockerfile: dockerfile parse error line 37: Unknown flag: link
[2023-04-10 15:38:26] │ 
[2023-04-10 15:38:26] │ command exited with code 1
[2023-04-10 15:38:26] │ 
[2023-04-10 15:38:26] │  ✘ build failed
```

Seems like we're making progress, but I need to go move the sprinklers again. Back soon!

11:59am: Sprinklers have been moved, and a shower (not via the sprinklers) has me refreshed. Time to sort out this problem.

Googling the error tells me that this might be due to the Dockerfile syntax, which can be set via a directive at the top of the file: https://stackoverflow.com/questions/74559925/dockerfile-parse-error-line-63-unknown-flag-link. Let's try that.

My build still failed, so clearly just setting the syntax to `syntax=docker/dockerfile:1.4` didn't fix it, but I wasn't really following all the directions so I guess I can't expect it to. Let's try enabling this "buildkit" mode by setting the env var `DOCKER_BUILDKIT=1`.

12:08pm: The env var didn't fix the issue, but maybe I don't even need this `--link` flag. I'm not honestly sure what it does. Google gets me to https://docs.docker.com/engine/reference/builder/#copy---link, which tells me `--link` is mostly a build time optimization, which I bet I can skip for now. Let's try removing it.

12:12pm: With the links removed, the build is making a lot more progress than before. Let's see if it completes.

12:18pm: build succeeded!? Definitely not fast. Maybe DO makes these builds slow so they can bill you for more build time.

Well, the build succeeded, but the deployment failed with the following error:

```
[2023-04-10 16:19:43] starting container: starting sub-container [rails server -p $PORT -e ${RAILS_ENV:-production}]: error finding executable "rails" in PATH [/usr/local/bundle/bin /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin]: no such file or directory
```

This one seems odd.

12:24pm: after some googling around not finding much, I've realized that I think I added this run command, and I don't think it makes much sense in this environment. The Dockerfile already sets up all the production env vars, and includes a `RUN` of its own to actually start the server. Lets try removing the `run_command` from my DO app spec. (I'm going to need to sort this out separately for my migrations job).

12:31pm: DO claims the deployment was successful! And the app is indeed live! If I'm honest, I wish I could get _some_ more confirmation that everything is now using Docker. Let's see what the deploy logs say.

12:34pm: Two interesting points. First, the build logs are clearly building a docker image, so I'll trust that everything is working there. Second, I apparently included a migration in this release that I had forgotten about (that tells you how much I'm paying attention), but it wasn't the migrations job that ran it, it was the main service!

By moving to the Dockerfile, I've noticed that my new `ENTRYPOINT` automatically runs `db:prepare` whenever it is run, which will _also_ automatically run migrations. So, I don't think I even need the job anymore. Let's just remove it now and clear up all of my earlier complaints about db migrations that are separate from the code deploys.

## Step three: Profit

12:47pm: Everything is working, and I've even deleted my database migrations job. This was even easier than I thought, largely thanks to rails having a gem for Dockerfiles. Thanks rails! Proof-reading this post, I've realized the true extent of the silliness of my previous setup. Astute readers will realize that my entirely commented out `bin/production-deploy.sh` script _already included_ a `db:prepare` call, but it was obviously doing nothing as it was. I think all I would have needed to avoid my post-deploy migrations job was uncommenting that line.

For me, that means today is already in the win column. I've moved my app to Docker, which will pave the way for my own clusters down the road. I've taken control of my build process, which removes a dependency on Digital Ocean. I've learned about how I should have been deploying and running migrations all along, and improved the "correctness" of my deployment processes to boot. A great day, and it's not even 1pm yet!

<hr>

Last week's post: [Deploying Barkeep](https://edbrown23.github.io/blog/2023/03/26/deployment-and-costs)
