# vectos.github.io

## Development

```
stack build
stack exec site build
stack exec site watch
```

## Deployment

So everything’s all setup and we’re ready to deploy.

> Note: Performing the following commands from your develop branch is recommended since you will end up back in that branch at the end.

Temporarily save any uncommitted changes that may exist in the current branch.

`git stash`

Ensure we are in the correct branch.

`git checkout develop`

Get a clean build of our site.

```
stack exec myblog clean
stack exec myblog build
```

Update the local list of remote branches to ensure we’re able to checkout the branch we want in the next step.

`git fetch --all`

Switch to the master branch.

> Note: Checking out this branch does not overwrite the files that Hakyll just produced because we have ’_site’ listed in both .gitignore files.

`git checkout -b master --track origin/master`

Next, copy the freshly made contents of ’_site’ over the old ones.

> Note: Deleting a file from your site’s source will not remove it from your master repository if it has already been published. An alternative to cp is discussed at the end of this guide.

`cp -a _site/. .`

Commit our changes.

```
git add -A
git commit -m "Publish."
```

And send them to GitHub.

`git push origin master:master`

Final clean up and return to the original state.

```
git checkout develop
git branch -D master
git stash pop
```
