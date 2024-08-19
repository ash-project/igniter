# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.3.20](https://github.com/ash-project/igniter/compare/v0.3.19...v0.3.20) (2024-08-19)




### Bug Fixes:

* ensure no timeout on task async streams

* don't hardcode `Foo.Supervisor` ð¤¦

## [v0.3.19](https://github.com/ash-project/igniter/compare/v0.3.18...v0.3.19) (2024-08-13)




### Bug Fixes:

* properly handle values vs code in configure

## [v0.3.18](https://github.com/ash-project/igniter/compare/v0.3.17...v0.3.18) (2024-08-08)




### Bug Fixes:

* fix and test keyword setting on empty list

## [v0.3.17](https://github.com/ash-project/igniter/compare/v0.3.16...v0.3.17) (2024-08-08)




### Bug Fixes:

* properly parse boolean switches from positional args

* don't warn on `Macro.Env.expand_alias/3` not being defined

* descend into single child block when modifying keyword

* set `format: :keyword` when adding keyword list item to empty list

* escape injected code in Common.replace_code/2 (#70)

* :error consistency in remove_keyword_key and argument_equals? in Config.configure (#68)

### Improvements:

* support for non-elixir files with create_new_file, update_file, include_existing_file, include_or_create_file, create_or_update_file (#75)

* support "notices" (#65)

## [v0.3.16](https://github.com/ash-project/igniter/compare/v0.3.15...v0.3.16) (2024-07-31)




### Bug Fixes:

* loadpaths after compiling deps

### Improvements:

* add `create_module` utility

## [v0.3.15](https://github.com/ash-project/igniter/compare/v0.3.14...v0.3.15) (2024-07-31)




### Bug Fixes:

* remove `force?: true` from dep installation

* better handling of positional args in igniter.new

## [v0.3.14](https://github.com/ash-project/igniter/compare/v0.3.13...v0.3.14) (2024-07-30)




### Bug Fixes:

* detect more function call formats

* properly extract arguments when parsing positional args

## [v0.3.13](https://github.com/ash-project/igniter/compare/v0.3.12...v0.3.13) (2024-07-30)




### Bug Fixes:

* force compile dependencies to avoid strange compiler issues

## [v0.3.12](https://github.com/ash-project/igniter/compare/v0.3.11...v0.3.12) (2024-07-30)




### Improvements:

* add `Igniter.Libs.Phoenix.endpoints_for_router/2`

## [v0.3.11](https://github.com/ash-project/igniter/compare/v0.3.10...v0.3.11) (2024-07-27)




### Bug Fixes:

* ensure igniter is compiled first

* fetch deps after adding any nested installers

* various fixes & improvements to positional argument listing

### Improvements:

* clean up dependency compiling logic

* optimize module finding w/ async_stream

* add `rest: true` option for positional args

## [v0.3.10](https://github.com/ash-project/igniter/compare/v0.3.9...v0.3.10) (2024-07-26)




### Bug Fixes:

* recompile igniter in `ingiter.install`

### Improvements:

* add `positional_args!/1` macro for use in tasks

* better output on missing installers & already present dep

## [v0.3.9](https://github.com/ash-project/igniter/compare/v0.3.8...v0.3.9) (2024-07-22)




### Bug Fixes:

* force compile dependencies.

* use length of path for insertion point, instead of node equality

## [v0.3.8](https://github.com/ash-project/igniter/compare/v0.3.7...v0.3.8) (2024-07-19)




### Improvements:

* better map key setting

* detect strings as non extendable blocks

* add option to ignore already present phoenix scopes

## [v0.3.7](https://github.com/ash-project/igniter/compare/v0.3.6...v0.3.7) (2024-07-19)




### Bug Fixes:

* improve `add_code` by modifying the `supertree`

## [v0.3.6](https://github.com/ash-project/igniter/compare/v0.3.5...v0.3.6) (2024-07-19)




### Bug Fixes:

* properly scope configuration modification code

* properly add blocks of code together

## [v0.3.5](https://github.com/ash-project/igniter/compare/v0.3.4...v0.3.5) (2024-07-19)




### Bug Fixes:

* properly move to pattern matches in scope

* configures?/3 -> configures_key & configures_root_key (#54)

### Improvements:

* add blocks together more fluidly in `add_code`

## [v0.3.4](https://github.com/ash-project/igniter/compare/v0.3.3...v0.3.4) (2024-07-19)

### Bug Fixes:

- recompile `:igniter` if it has to

### Improvements:

- include config in include_all_elixir_files (#55)

- add Function.argument_equals?/3 (#53)

- add Function.argument_equals?/3

## [v0.3.3](https://github.com/ash-project/igniter/compare/v0.3.2...v0.3.3) (2024-07-18)

### Improvements:

- fix function typespecs & add `inflex` dependency

- only show executed installers (#50)

- support tuple dependencies in igniter.install (#49)

## [v0.3.2](https://github.com/ash-project/igniter/compare/v0.3.1...v0.3.2) (2024-07-16)

### Bug Fixes:

- don't compile igniter dep again when compiling deps

## [v0.3.1](https://github.com/ash-project/igniter/compare/v0.3.0...v0.3.1) (2024-07-16)

### Bug Fixes:

- when adding code to surrounding block, don't go up multiple blocks

## [v0.3.0](https://github.com/ash-project/igniter/compare/v0.2.13...v0.3.0) (2024-07-15)

### Improvements:

- Add `Igniter.Libs.Phoenix` for working with Phoenix

- deprecate duplicate `Igniter.Code.Module.move_to_use` function

- `Igniter.Project.Config.configures?/4` that takes a config file

- Add `Igniter.Util.Warning` for formatting code in warnings

## [v0.2.13](https://github.com/ash-project/igniter/compare/v0.2.12...v0.2.13) (2024-07-15)

### Bug Fixes:

- remove redundant case clause in `Igniter.Code.Common`

### Improvements:

- make `apply_and_fetch_dependencies` only change `deps/0`

- remove a bunch of dependencies by using :inets & :httpc

## [v0.2.12](https://github.com/ash-project/igniter/compare/v0.2.11...v0.2.12) (2024-07-10)

### Bug Fixes:

- fix dialyzer warnings about info/2 never being nil

## [v0.2.11](https://github.com/ash-project/igniter/compare/v0.2.10...v0.2.11) (2024-07-10)

### Bug Fixes:

- prevent crash on specific cases with `igniter.new`

### Improvements:

- more consistent initial impl of `elixirc_paths`

- support :kind in find_and_update_or_create_module/5 (#38)

## [v0.2.10](https://github.com/ash-project/igniter/compare/v0.2.9...v0.2.10) (2024-07-10)

### Improvements:

- ensure `test/support` is in elixirc paths automatically when necessary

## [v0.2.9](https://github.com/ash-project/igniter/compare/v0.2.8...v0.2.9) (2024-07-09)

### Bug Fixes:

- simplify how we get tasks to run

- don't try to format after editing `mix.exs`

## [v0.2.8](https://github.com/ash-project/igniter/compare/v0.2.7...v0.2.8) (2024-07-09)

### Bug Fixes:

- fix deps compilation issues by vendoring `deps.compile`

- honor `--yes` flag when installing deps always

### Improvements:

- small tweaks to output

## [v0.2.7](https://github.com/ash-project/igniter/compare/v0.2.6...v0.2.7) (2024-07-09)

### Bug Fixes:

- remove shortnames for global options, to reduce conflicts

- remove erroneous warning while composing tasks

- pass file_path to `ensure_default_configs_exist` (#36)

- preserve original ordering in Util.Install (#33)

- include only "mix.exs" in the actual run in apply_and_fetch_dependencies (#32)

- always return {:ok, zipper} in append_new_to_list/2 (#31)

### Improvements:

- support an optional append? flag for add_dep/3 (#34)

- add `add_dep/2-3`, that accepts a full dep specification

- deprecate `add_dependency/3-4`

- make module moving much smarter

- add configurations for not moving certain modules

- make `source_folders` configurable

## [v0.2.6](https://github.com/ash-project/igniter/compare/v0.2.5...v0.2.6) (2024-07-02)

### Improvements:

- properly find nested modules again

- make igniter tests much faster by not searching our own project

- add `include_all_elixir_files/1`

- add `module_exists?/2`

- add `find_and_update_module/3`

- only require rejecting mix deps.get one time & remember that choice

- simpler messages signaling a mix deps.get

## [v0.2.5](https://github.com/ash-project/igniter/compare/v0.2.4...v0.2.5) (2024-07-02)

### Improvements:

- `move_modules` -> `move_files`

- move some files around and update config names

- use `%Info{}` structs to compose and plan nested installers

- add Igniter.apply_and_fetch_dependencies/1 and Igniter.has_changes?/1 (#28)

- rename option_schema/2 -> info/2

- only create default configs if an env-specific config is created

## [v0.2.4](https://github.com/ash-project/igniter/compare/v0.2.3...v0.2.4) (2024-06-28)

### Bug Fixes:

- fix match error in `append_new_to_list`

- version string splitting (#25)

### Improvements:

- add an optional path argument to `find_and_update_or_create_module/5`

- add `option_schema/2` callback to `Igniter.Mix.Task`

- `Module.find_and_update_or_create_module`

- add a way to move files

- add `.igniter.exs` file, and `mix igniter.setup` to create it

- move files to configured location based on changes

- add fallback to compose_task (#19)

- add proper_test_support_location/1 (#18)

- add proper_test_location/1 (#17)

## [v0.2.3](https://github.com/ash-project/igniter/compare/v0.2.2...v0.2.3) (2024-06-21)

### Improvements:

- use `override: true` for git/github deps as well

## [v0.2.2](https://github.com/ash-project/igniter/compare/v0.2.1...v0.2.2) (2024-06-21)

### Bug Fixes:

- don't show unnecessary diff output

- don't compile before fetching deps

## [v0.2.1](https://github.com/ash-project/igniter/compare/v0.2.0...v0.2.1) (2024-06-21)

### Improvements:

- workaround trailing comment issues w/ sourceror

- support `--with` option in `igniter.new`

## [v0.2.0](https://github.com/ash-project/igniter/compare/v0.1.8...v0.2.0) (2024-06-20)

### Improvements:

- make installer use `override: true` on local dependency

- ensure dependencies are compiled after `mix deps.get`

- use warnings instead of errors for better UX

- move proejct related things to `Project` namespace

## [v0.1.8](https://github.com/ash-project/igniter/compare/v0.1.7...v0.1.8) (2024-06-19)

### Bug Fixes:

- update spitfire for env fix

### Improvements:

- rename `env_at_cursor` to `current_env`

- improve marshalling of spitfire env to macro env

- show warning when adding dependencies by default

## [v0.1.7](https://github.com/ash-project/igniter/compare/v0.1.6...v0.1.7) (2024-06-14)

### Improvements:

- various restructurings and improvements across the board

- use `Spitfire` to ensure that aliases are considered when comparing modules

- use `Spitfire` to _use_ any existing aliases when inserting code

- use `Zipper.topmost` to power new `Spitfire`-related features

## [v0.1.6](https://github.com/ash-project/igniter/compare/v0.1.5...v0.1.6) (2024-06-13)

### Bug Fixes:

- patch formatter fix, to be removed later when rewrite PR is merged

- properly find functions in scope

## [v0.1.5](https://github.com/ash-project/igniter/compare/v0.1.4...v0.1.5) (2024-06-13)

### Bug Fixes:

- Igniter.Code.Common.with/2 was not properly merging with original zipper

## [v0.1.4](https://github.com/ash-project/igniter/compare/v0.1.3...v0.1.4) (2024-06-13)

### Improvements:

- use `path:` prefix instead of `local:`

## [v0.1.3](https://github.com/ash-project/igniter/compare/v0.1.2...v0.1.3) (2024-06-13)

### Improvements:

- support space-separated installers

## [v0.1.2](https://github.com/ash-project/igniter/compare/v0.1.1...v0.1.2) (2024-06-13)

### Bug Fixes:

- remove unsupportable package installation symbols

- don't run `mix deps.get` if dependency changes are aborted

## [v0.1.1](https://github.com/ash-project/igniter/compare/v0.1.0...v0.1.1) (2024-06-13)

### Bug Fixes:

- always format the file even if no `.formatter.exs` exists

## [v0.1.0](https://github.com/ash-project/igniter/compare/v0.1.0...v0.1.0) (2024-06-13)

### Bug Fixes:

- handle existing deps when they are not local properly

### Improvements:

- ignore installer tasks that are not igniter tasks

- draw the rest of the owl

- add installer archive

- more module helpers

- wrap code in `==code==` so you can tell what is being `puts`

- add CI/build and get it passing locally
