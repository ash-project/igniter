# Releasing igniter

This documents the method of releasing igniter. You first need access to both the hex package
and the GH repo.

## `mix git_ops.release`

Run `mix git_ops.release` to generate a new changelog and bump the version.

This will instruct you to then run `git push --follow-tags`. You can also
modify the changelog while the prompt is active and before confirming if
you want to clean it up a bit. I typically format the file and adjust things
to make it a bit clearer.

## `mix hex.publish`

You *typically* won't need to do this, but if CI fails for some reason, or you are in a hurry,
you can run `mix hex.publish` to publish the hex package. CI will fail if you publish it
before CI gets to tha step. This is fine.

## publishing the installer `igniter_new`

The process for this is less rigorous. You manually bump the verison in `installer/mix.exs`,
cd into `/installer` and then run `mix hex.publish`, and thats it :)
If you've published a new version of `igniter` that should affect what version the
installer uses, edit `@igniter_version` module attribute in `installer/lib/mix/tasks/igniter.new.ex`
to match the new requirement.
