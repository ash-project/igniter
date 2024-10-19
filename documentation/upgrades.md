# Upgrades

Igniter provides a mix task `mix igniter.upgrade` that is a drop-in replacement for
`mix deps.update`, but will run any associated `upgrade` tasks for the packages that have changed.

## Using Upgraders

In general, you can replace your usage of `mix deps.update` with `mix igniter.upgrade`. Packages that
don't use igniter will be updated as normal, and packages that do will have any associated upgraders run.

## Writing Upgraders

To write an upgrader, your package should provide an igniter task called `your_package.upgrade`. This task
will take two positional arguments, `from` and `to`, which are the old and new versions of the package.

While you are free to implement this logic however you like, we suggest using
`mix igniter.gen.task your_package.upgrade --upgrade`, and following the patterns that are provided by the generated task.

## Limitations

### Compile Compatibility

The new version of the package must be "compile compatible" with your existing code. For this reason,
we encourage library authors to make even _major_ versions compile compatible with previous versions, but
this is not always possible. For those cases, we encourage library authors to provide a version _prior_
to their breaking changes that includs an upgrader to code that is compatible with the new version. This way,
you can at least instruct users to `mix igniter.upgrade package@that.version` before upgrading to the latest
version.

### Path dependencies

We cannot determine the old version for path dependencies, so currently there is no way to use
them with `mix igniter.upgrade`. We can potentially support this in the future with arguments
like `--old-version-<dep-name> x.y.z`.

## Upgrading in CI (i.e Dependabot)

The flag `--git-ci` is provided to `mix igniter.upgrade` to allow for CI integration. This flag
causes igniter to parse the previous versions from the `mix.lock` file prior to the current pull request.
This limitation does mean that only hex dependencies can be upgraded in this way.
Here is an example set of github action steps that will run `mix igniter.upgrade` and add a commit
for any upgrades.

```yml
- name: Dependabot metadata
  id: dependabot-metadata
  uses: dependabot/fetch-metadata@4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d
  if: github.event.pull_request.user.login == 'dependabot[bot]'
  with:
    github-token: "${{ secrets.GITHUB_TOKEN }}"
- name: mix upgrade
  if: github.event.pull_request.user.login == 'dependabot[bot]'
  run: mix igniter.upgrade ${{steps.dependabot-metadata.outputs.dependency-names}} --git-ci
- name: Commit Changes
  uses: stefanzweifel/git-auto-commit-action@v5
  if: github.event.pull_request.user.login == 'dependabot[bot]'
  with:
    commit_message: Apply Igniter Upgrades
    commit_user_name: Igniter
    commit_user_email: igniter@ash-hq.org
    commit_author: Igniter Upgrade Bot <igniter@ash-hq.org>
```
