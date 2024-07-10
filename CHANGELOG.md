# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.2.12](https://github.com/ash-project/igniter/compare/v0.2.11...v0.2.12) (2024-07-10)




### Bug Fixes:

* fix dialyzer warnings about info/2 never being nil

## [v0.2.11](https://github.com/ash-project/igniter/compare/v0.2.10...v0.2.11) (2024-07-10)




### Bug Fixes:

* prevent crash on specific cases with `igniter.new`

### Improvements:

* more consistent initial impl of `elixirc_paths`

* support :kind in find_and_update_or_create_module/5 (#38)

## [v0.2.10](https://github.com/ash-project/igniter/compare/v0.2.9...v0.2.10) (2024-07-10)




### Improvements:

* ensure `test/support` is in elixirc paths automatically when necessary

## [v0.2.9](https://github.com/ash-project/igniter/compare/v0.2.8...v0.2.9) (2024-07-09)




### Bug Fixes:

* simplify how we get tasks to run

* don't try to format after editing `mix.exs`

## [v0.2.8](https://github.com/ash-project/igniter/compare/v0.2.7...v0.2.8) (2024-07-09)




### Bug Fixes:

* fix deps compilation issues by vendoring `deps.compile`

* honor `--yes` flag when installing deps always

### Improvements:

* small tweaks to output

## [v0.2.7](https://github.com/ash-project/igniter/compare/v0.2.6...v0.2.7) (2024-07-09)




### Bug Fixes:

* remove shortnames for global options, to reduce conflicts

* remove erroneous warning while composing tasks

* pass file_path to `ensure_default_configs_exist` (#36)

* preserve original ordering in Util.Install (#33)

* include only "mix.exs" in the actual run in apply_and_fetch_dependencies (#32)

* always return {:ok, zipper} in append_new_to_list/2 (#31)

### Improvements:

* support an optional append? flag for add_dep/3 (#34)

* add `add_dep/2-3`, that accepts a full dep specification

* deprecate `add_dependency/3-4`

* make module moving much smarter

* add configurations for not moving certain modules

* make `source_folders` configurable

## [v0.2.6](https://github.com/ash-project/igniter/compare/v0.2.5...v0.2.6) (2024-07-02)




### Improvements:

* properly find nested modules again

* make igniter tests much faster by not searching our own project

* add `include_all_elixir_files/1`

* add `module_exists?/2`

* add `find_and_update_module/3`

* only require rejecting mix deps.get one time & remember that choice

* simpler messages signaling a mix deps.get

## [v0.2.5](https://github.com/ash-project/igniter/compare/v0.2.4...v0.2.5) (2024-07-02)




### Improvements:

* `move_modules` -> `move_files`

* move some files around and update config names

* use `%Info{}` structs to compose and plan nested installers

* add Igniter.apply_and_fetch_dependencies/1 and Igniter.has_changes?/1 (#28)

* rename option_schema/2 -> info/2

* only create default configs if an env-specific config is created

## [v0.2.4](https://github.com/ash-project/igniter/compare/v0.2.3...v0.2.4) (2024-06-28)




### Bug Fixes:

* fix match error in `append_new_to_list`

* version string splitting (#25)

### Improvements:

* add an optional path argument to `find_and_update_or_create_module/5`

* add `option_schema/2` callback to `Igniter.Mix.Task`

* `Module.find_and_update_or_create_module`

* add a way to move files

* add `.igniter.exs` file, and `mix igniter.setup` to create it

* move files to configured location based on changes

* add fallback to compose_task (#19)

* add proper_test_support_location/1 (#18)

* add proper_test_location/1 (#17)

## [v0.2.3](https://github.com/ash-project/igniter/compare/v0.2.2...v0.2.3) (2024-06-21)




### Improvements:

* use `override: true` for git/github deps as well

## [v0.2.2](https://github.com/ash-project/igniter/compare/v0.2.1...v0.2.2) (2024-06-21)




### Bug Fixes:

* don't show unnecessary diff output

* don't compile before fetching deps

## [v0.2.1](https://github.com/ash-project/igniter/compare/v0.2.0...v0.2.1) (2024-06-21)




### Improvements:

* workaround trailing comment issues w/ sourceror

* support `--with` option in `igniter.new`

## [v0.2.0](https://github.com/ash-project/igniter/compare/v0.1.8...v0.2.0) (2024-06-20)




### Improvements:

* make installer use `override: true` on local dependency

* ensure dependencies are compiled after `mix deps.get`

* use warnings instead of errors for better UX

* move proejct related things to `Project` namespace

## [v0.1.8](https://github.com/ash-project/igniter/compare/v0.1.7...v0.1.8) (2024-06-19)




### Bug Fixes:

* update spitfire for env fix

### Improvements:

* rename `env_at_cursor` to `current_env`

* improve marshalling of spitfire env to macro env

* show warning when adding dependencies by default

## [v0.1.7](https://github.com/ash-project/igniter/compare/v0.1.6...v0.1.7) (2024-06-14)




### Improvements:

* various restructurings and improvements across the board

* use `Spitfire` to ensure that aliases are considered when comparing modules

* use `Spitfire` to *use* any existing aliases when inserting code

* use `Zipper.topmost` to power new `Spitfire`-related features

## [v0.1.6](https://github.com/ash-project/igniter/compare/v0.1.5...v0.1.6) (2024-06-13)




### Bug Fixes:

* patch formatter fix, to be removed later when rewrite PR is merged

* properly find functions in scope

## [v0.1.5](https://github.com/ash-project/igniter/compare/v0.1.4...v0.1.5) (2024-06-13)




### Bug Fixes:

* Igniter.Code.Common.with/2 was not properly merging with original zipper

## [v0.1.4](https://github.com/ash-project/igniter/compare/v0.1.3...v0.1.4) (2024-06-13)




### Improvements:

* use `path:` prefix instead of `local:`

## [v0.1.3](https://github.com/ash-project/igniter/compare/v0.1.2...v0.1.3) (2024-06-13)




### Improvements:

* support space-separated installers

## [v0.1.2](https://github.com/ash-project/igniter/compare/v0.1.1...v0.1.2) (2024-06-13)




### Bug Fixes:

* remove unsupportable package installation symbols

* don't run `mix deps.get` if dependency changes are aborted

## [v0.1.1](https://github.com/ash-project/igniter/compare/v0.1.0...v0.1.1) (2024-06-13)




### Bug Fixes:

* always format the file even if no `.formatter.exs` exists

## [v0.1.0](https://github.com/ash-project/igniter/compare/v0.1.0...v0.1.0) (2024-06-13)




### Bug Fixes:

* handle existing deps when they are not local properly

### Improvements:

* ignore installer tasks that are not igniter tasks

* draw the rest of the owl

* add installer archive

* more module helpers

* wrap code in `==code==` so you can tell what is being `puts`

* add CI/build and get it passing locally
