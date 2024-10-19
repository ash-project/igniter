# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.3.67](https://github.com/ash-project/igniter/compare/v0.3.66...v0.3.67) (2024-10-19)




### Bug Fixes:

* ensure deps are always added in explicit tuple format

* don't use the 2 arg version of config when the first key would be ugly

## [v0.3.66](https://github.com/ash-project/igniter/compare/v0.3.65...v0.3.66) (2024-10-19)




### Improvements:

* significant improvements to function checking speed

## [v0.3.65](https://github.com/ash-project/igniter/compare/v0.3.64...v0.3.65) (2024-10-19)




### Improvements:

* add `mix igniter.upgrade`

* add `mix igniter.refactor.rename_function`

## [v0.3.64](https://github.com/ash-project/igniter/compare/v0.3.63...v0.3.64) (2024-10-17)




### Bug Fixes:

* don't infinitely recurse on update_all_matches

* detect node removal in update_all_matches

### Improvements:

* add `Igniter.Code.String`

## [v0.3.63](https://github.com/ash-project/igniter/compare/v0.3.62...v0.3.63) (2024-10-15)




### Bug Fixes:

* properly collect csv options into lists

## [v0.3.62](https://github.com/ash-project/igniter/compare/v0.3.61...v0.3.62) (2024-10-14)




### Bug Fixes:

* properly parse csv/keep options

## [v0.3.61](https://github.com/ash-project/igniter/compare/v0.3.60...v0.3.61) (2024-10-14)




### Improvements:

* support csv option type and properly handle keep options lists

## [v0.3.60](https://github.com/ash-project/igniter/compare/v0.3.59...v0.3.60) (2024-10-14)




### Improvements:

* don't rely on elixir 1.16+ features

## [v0.3.59](https://github.com/ash-project/igniter/compare/v0.3.58...v0.3.59) (2024-10-14)




### Bug Fixes:

* don't return igniter from message function

## [v0.3.58](https://github.com/ash-project/igniter/compare/v0.3.57...v0.3.58) (2024-10-13)




### Bug Fixes:

* don't assume the availabilit of `which`

## [v0.3.57](https://github.com/ash-project/igniter/compare/v0.3.56...v0.3.57) (2024-10-11)




### Improvements:

* add `group` and option disambiguation based on groups

## [v0.3.56](https://github.com/ash-project/igniter/compare/v0.3.55...v0.3.56) (2024-10-11)




### Improvements:

* support required arguments in the info schema

## [v0.3.55](https://github.com/ash-project/igniter/compare/v0.3.54...v0.3.55) (2024-10-11)




### Bug Fixes:

* fix pattern match on prompt on git changes

## [v0.3.54](https://github.com/ash-project/igniter/compare/v0.3.53...v0.3.54) (2024-10-11)




### Bug Fixes:

* looser match on git change detection

## [v0.3.53](https://github.com/ash-project/igniter/compare/v0.3.52...v0.3.53) (2024-10-11)




### Improvements:

* add `on_exists` handling to `Igniter.Libs.Ecto.gen_migration`

## [v0.3.52](https://github.com/ash-project/igniter/compare/v0.3.51...v0.3.52) (2024-10-07)




### Improvements:

* properly warn on git changes before committing

## [v0.3.51](https://github.com/ash-project/igniter/compare/v0.3.50...v0.3.51) (2024-10-07)




### Bug Fixes:

* provide proper version in the installer

### Improvements:

* remove `System.cmd` for `igniter.install` in installer

* allow excluding line numbers in `Igniter.Test.assert_has_patch`

* prettier errors on task exits

## [v0.3.50](https://github.com/ash-project/igniter/compare/v0.3.49...v0.3.50) (2024-10-07)




### Improvements:

* don't warn on missing installers that aren't actually missing

## [v0.3.49](https://github.com/ash-project/igniter/compare/v0.3.48...v0.3.49) (2024-10-06)




### Bug Fixes:

* fix dialyzer spec

## [v0.3.48](https://github.com/ash-project/igniter/compare/v0.3.47...v0.3.48) (2024-10-04)




### Improvements:

* add `opts_updater` option to `add_new_child`

* add `Igniter.Libs.Ecto.gen_migration`

* implement various deprecations

* add `Igniter.Libs.Ecto` for listing/selecting repos

* add `defaults` key to `Info{}`

## [v0.3.47](https://github.com/ash-project/igniter/compare/v0.3.46...v0.3.47) (2024-10-04)




### Bug Fixes:

* prompt users to handle diverged environment issues

* display installer output in `IO.stream()`

* honor --yes properly when adding nested deps

* don't install revoked versions of packages

* install non-rc packages, or the rc package if there is none

## [v0.3.46](https://github.com/ash-project/igniter/compare/v0.3.45...v0.3.46) (2024-10-03)




### Bug Fixes:

* fix message in task name warning

## [v0.3.45](https://github.com/ash-project/igniter/compare/v0.3.44...v0.3.45) (2024-09-25)




### Bug Fixes:

* use `ensure_all_started` without a list for backwards compatibility

### Improvements:

* Yn -> y/n to represent a lack of a default

## [v0.3.44](https://github.com/ash-project/igniter/compare/v0.3.43...v0.3.44) (2024-09-24)




### Bug Fixes:

* properly create or update config files

* format files after reading so formatter_opts is set before later writes

* remove incorrect call to `add_code` from `replace_code`

## [v0.3.43](https://github.com/ash-project/igniter/compare/v0.3.42...v0.3.43) (2024-09-23)




### Bug Fixes:

* traverse lists without entering child nodes

## [v0.3.42](https://github.com/ash-project/igniter/compare/v0.3.41...v0.3.42) (2024-09-23)




### Bug Fixes:

* handle empty requested positional args when extracting positional

### Improvements:

* add `Igniter.Code.List.replace_in_list/3`

* allow appending/prepending a different value when the full

## [v0.3.41](https://github.com/ash-project/igniter/compare/v0.3.40...v0.3.41) (2024-09-23)




### Improvements:

* add `Igniter.Project.TaskAliases.add_alias/3-4`

## [v0.3.40](https://github.com/ash-project/igniter/compare/v0.3.39...v0.3.40) (2024-09-23)




### Bug Fixes:

* properly detect existing scopes with matching names

## [v0.3.39](https://github.com/ash-project/igniter/compare/v0.3.38...v0.3.39) (2024-09-18)




### Bug Fixes:

* don't warn while parsing files

* display an error when a composed task can't be found

### Improvements:

* more phoenix router specific code

* make `issues` red and formatted with more spacing

* properly compare regex literals

* add `dont_move_file_pattern` utility

* update installer to always run mix deps get and install

## [v0.3.38](https://github.com/ash-project/igniter/compare/v0.3.37...v0.3.38) (2024-09-16)




### Bug Fixes:

* don't add warning on `overwrite` option

### Improvements:

* better confirmation message experience

## [v0.3.37](https://github.com/ash-project/igniter/compare/v0.3.36...v0.3.37) (2024-09-15)




### Improvements:

* return `igniter` in `Igniter.Test.assert_unchanged`

## [v0.3.36](https://github.com/ash-project/igniter/compare/v0.3.35...v0.3.36) (2024-09-13)




### Bug Fixes:

* reevaluate .igniter.exs when it changes

### Improvements:

* Support for extensions in igniter config

* Add a phoenix extension to prevent moving modules that may be phoenix-y

## [v0.3.35](https://github.com/ash-project/igniter/compare/v0.3.34...v0.3.35) (2024-09-10)




### Bug Fixes:

* much smarter removal of `import_config` when evaluating configuration files

* when including a glob, use `test_files` in test_mode

### Improvements:

* add `Igniter.Code.Common.remove/2`

## [v0.3.34](https://github.com/ash-project/igniter/compare/v0.3.33...v0.3.34) (2024-09-10)




### Bug Fixes:

* properly avoid adding duplicate children to application tree

## [v0.3.33](https://github.com/ash-project/igniter/compare/v0.3.32...v0.3.33) (2024-09-10)




### Bug Fixes:

* properly determine module placement in app tree

## [v0.3.32](https://github.com/ash-project/igniter/compare/v0.3.31...v0.3.32) (2024-09-10)




### Bug Fixes:

* properly extract app module from `def project`

## [v0.3.31](https://github.com/ash-project/igniter/compare/v0.3.30...v0.3.31) (2024-09-10)




### Bug Fixes:

* set only option to `nil` by default

## [v0.3.30](https://github.com/ash-project/igniter/compare/v0.3.29...v0.3.30) (2024-09-10)




### Bug Fixes:

* handle some edge cases in application child adding

### Improvements:

* support the opts being code when adding a new child to the app tree

* prepend new children instead of appending them

* add an `after` option to `add_new_child/3`

* better warnings on invalid patches in test

## [v0.3.29](https://github.com/ash-project/igniter/compare/v0.3.28...v0.3.29) (2024-09-09)

### Improvements:

- check for git changes to avoid overwriting unsaved changes

- add `mix igniter.gen.task` to quickly generate a full task

- properly find the default location for mix task modules

- add `--only` option, and `only` key in `Igniter.Mix.Task.Info`

- add `Igniter.Test` with helpers for writing tests

- extract app name and app module from mix.exs file

## [v0.3.28](https://github.com/ash-project/igniter/compare/v0.3.27...v0.3.28) (2024-09-09)

### Bug Fixes:

- don't hardcode `Spark.Formatter` plugin

## [v0.3.27](https://github.com/ash-project/igniter/compare/v0.3.26...v0.3.27) (2024-09-08)

### Improvements:

- when replacing a dependency, leave it in the same location

## [v0.3.26](https://github.com/ash-project/igniter/compare/v0.3.25...v0.3.26) (2024-09-08)

### Improvements:

- add `igniter.update_gettext`

## [v0.3.25](https://github.com/ash-project/igniter/compare/v0.3.24...v0.3.25) (2024-09-06)

### Improvements:

- add `configure_runtime_env` codemod

- remove dependencies that aren't strictly necessary

- remove dependencies that we don't really need

- more options to `igniter.new`

## [v0.3.24](https://github.com/ash-project/igniter/compare/v0.3.23...v0.3.24) (2024-08-26)

### Bug Fixes:

- detect equal lists for node equality

## [v0.3.23](https://github.com/ash-project/igniter/compare/v0.3.22...v0.3.23) (2024-08-26)

### Bug Fixes:

- properly move to arguments of Module.fun calls

### Improvements:

- add `Igniter.Code.Common.expand_literal/1`

- add `--with-args` to pass additional args to installers

## [v0.3.22](https://github.com/ash-project/igniter/compare/v0.3.21...v0.3.22) (2024-08-20)

### Improvements:

- add options to control behavior when creating a file that already exists

## [v0.3.21](https://github.com/ash-project/igniter/compare/v0.3.20...v0.3.21) (2024-08-20)

### Improvements:

- add `copy_template/4`

## [v0.3.20](https://github.com/ash-project/igniter/compare/v0.3.19...v0.3.20) (2024-08-19)

### Bug Fixes:

- ensure no timeout on task async streams

- don't hardcode `Foo.Supervisor` ð¤¦

## [v0.3.19](https://github.com/ash-project/igniter/compare/v0.3.18...v0.3.19) (2024-08-13)

### Bug Fixes:

- properly handle values vs code in configure

## [v0.3.18](https://github.com/ash-project/igniter/compare/v0.3.17...v0.3.18) (2024-08-08)

### Bug Fixes:

- fix and test keyword setting on empty list

## [v0.3.17](https://github.com/ash-project/igniter/compare/v0.3.16...v0.3.17) (2024-08-08)

### Bug Fixes:

- properly parse boolean switches from positional args

- don't warn on `Macro.Env.expand_alias/3` not being defined

- descend into single child block when modifying keyword

- set `format: :keyword` when adding keyword list item to empty list

- escape injected code in Common.replace_code/2 (#70)

- :error consistency in remove_keyword_key and argument_equals? in Config.configure (#68)

### Improvements:

- support for non-elixir files with create_new_file, update_file, include_existing_file, include_or_create_file, create_or_update_file (#75)

- support "notices" (#65)

## [v0.3.16](https://github.com/ash-project/igniter/compare/v0.3.15...v0.3.16) (2024-07-31)

### Bug Fixes:

- loadpaths after compiling deps

### Improvements:

- add `create_module` utility

## [v0.3.15](https://github.com/ash-project/igniter/compare/v0.3.14...v0.3.15) (2024-07-31)

### Bug Fixes:

- remove `force?: true` from dep installation

- better handling of positional args in igniter.new

## [v0.3.14](https://github.com/ash-project/igniter/compare/v0.3.13...v0.3.14) (2024-07-30)

### Bug Fixes:

- detect more function call formats

- properly extract arguments when parsing positional args

## [v0.3.13](https://github.com/ash-project/igniter/compare/v0.3.12...v0.3.13) (2024-07-30)

### Bug Fixes:

- force compile dependencies to avoid strange compiler issues

## [v0.3.12](https://github.com/ash-project/igniter/compare/v0.3.11...v0.3.12) (2024-07-30)

### Improvements:

- add `Igniter.Libs.Phoenix.endpoints_for_router/2`

## [v0.3.11](https://github.com/ash-project/igniter/compare/v0.3.10...v0.3.11) (2024-07-27)

### Bug Fixes:

- ensure igniter is compiled first

- fetch deps after adding any nested installers

- various fixes & improvements to positional argument listing

### Improvements:

- clean up dependency compiling logic

- optimize module finding w/ async_stream

- add `rest: true` option for positional args

## [v0.3.10](https://github.com/ash-project/igniter/compare/v0.3.9...v0.3.10) (2024-07-26)

### Bug Fixes:

- recompile igniter in `ingiter.install`

### Improvements:

- add `positional_args!/1` macro for use in tasks

- better output on missing installers & already present dep

## [v0.3.9](https://github.com/ash-project/igniter/compare/v0.3.8...v0.3.9) (2024-07-22)

### Bug Fixes:

- force compile dependencies.

- use length of path for insertion point, instead of node equality

## [v0.3.8](https://github.com/ash-project/igniter/compare/v0.3.7...v0.3.8) (2024-07-19)

### Improvements:

- better map key setting

- detect strings as non extendable blocks

- add option to ignore already present phoenix scopes

## [v0.3.7](https://github.com/ash-project/igniter/compare/v0.3.6...v0.3.7) (2024-07-19)

### Bug Fixes:

- improve `add_code` by modifying the `supertree`

## [v0.3.6](https://github.com/ash-project/igniter/compare/v0.3.5...v0.3.6) (2024-07-19)

### Bug Fixes:

- properly scope configuration modification code

- properly add blocks of code together

## [v0.3.5](https://github.com/ash-project/igniter/compare/v0.3.4...v0.3.5) (2024-07-19)

### Bug Fixes:

- properly move to pattern matches in scope

- configures?/3 -> configures_key & configures_root_key (#54)

### Improvements:

- add blocks together more fluidly in `add_code`

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
