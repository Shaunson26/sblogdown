---
title: SSH GitHub Action
author: Shaun Nielsen
date: '2023-01-26'
slug: []
categories: []
tags: [
    "GitHub Actions",
    "CI/CD"
]
weight: 50
show_comments: yes
katex: no
draft: yes
---

Today I configured a GitHub Action to SSH my server and pull the main branch
after a successful PR. Here's how ...

<!--more-->

## Background

I was needing to explore some CI/CD stuffs, specifically how the CD part works.
I wanted to start small. I have a [repo that holds my simple CV webpage](https://github.com/Shaunson26/CV-webpage)
and which is being hosted on my own sandbox VM - [shaunnielsen.com](https://shaunnielsen.com).
Given I would generally update the repo locally and push to GitHub, I would then have 
to 1) log in into the server, 2) navigate to the folder and 3) pull the changes to have
the most recent version be served.

I expected that I would be able to use a GitHub Action to SSH into my server and
do a `git pull` after changes were pushed to the `main` branch. Searching the internet
revealed this to be a relatively simple task. This is how it was done ...

### An SSH GitHub Action

I googled `github ssh action` and the top hit led me to - https://github.com/appleboy/ssh-action.
I noticed it had about 30 K users (2023-01-26), so it looked like the real deal.

In the simplest case, all it requires are the `HOST`, `USERNAME`, `PASSWORD`, `PORT`
and some terminal commands (e.g. `whoami`, `ls -al`).

```
name: remote ssh command
on: [push]
jobs:

  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
    - name: executing remote ssh commands using password
      uses: appleboy/ssh-action@v0.1.7
      with:
        host: ${{ secrets.HOST }}
        username: ${{ secrets.USERNAME }}
        password: ${{ secrets.PASSWORD }}
        port: ${{ secrets.PORT }}
        script: |
          whoami
          ls -al
```

All I was required to do was to set up my secrets within the GitHub repo and
determine my terminal commands.

### GitHub repo secrets

Another google of `github secrets` led me to the [relevant GitHub Docs](https://docs.github.com/en/actions/security-guides/encrypted-secrets). Within
the repo, you go to

  - the `Settings` tab, 
  - click on `Secrets and variables` in sidebar,
  - and click the `Actions` sub-link. 
  
Here you create your repo secrets that would be referenced in your actions 
YAML e.g. `${{ secrets.USERNAME }}`. Simply click the `New repository secret` button.

![secrets page screenshot](figures/github-secrets-page.PNG)

I created the required secrets for the GitHub SSH Action but also thought to keep 
the path of repo secret as well - otherwise these details show up in the public action
logs.

### My SSH action

I created a simple action as follows

  - when a push occurs to the `main` branch (through a PR)
  - use the action `appleboy/ssh-action@v0.1.7`
  - on the server  
      - `cd` to the repo directory
      - ensure the `main` branch is checked out
      - `git pull` the latest change

```
name: Deploy to server

on:
  push:
    branches: [main]

jobs:
  deploy:
    name: Deploy to server
    runs-on: ubuntu-latest
    steps:
    - name: executing remote ssh commands using password
      uses: appleboy/ssh-action@v0.1.7
      with:
        host: ${{ secrets.HOST }}
        username: ${{ secrets.USERNAME }}
        password: ${{ secrets.PASSWORD }}
        port: ${{ secrets.PORT }}
        script: |
          cd ${{ secrets.PATH }}
          git checkout main
          git pull
```

I created a branch, made some changes and PR'd them to main. The action
ran as expected (well, after some trial and error that we can easily omit here!)

![Action result](figures/deploy-result.PNG)

## Conclusion

A simple SSH action was created here thanks to `appleboy/ssh-action`. This example
may be overly simple, as a real world case might involve unit testing and whatnot
to pass before the deployment occurs. I'm sure there are examples out there and
that is what I will be looking at next.





