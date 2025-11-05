<!--
SPDX-FileCopyrightText: 2020 Zach Daniel
SPDX-FileCopyrightText: 2024 igniter contributors <https://github.com/ash-project/igniter/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.7.0](https://github.com/ash-project/igniter/compare/v0.6.30...v0.7.0) (2025-11-05)




### Features:

* Add support for SiteEncrypt.Phoenix.Endpoint detection (#339) by Herman verschooten

### Bug Fixes:

* `put_in_map`/`set_map_key` not setting keys properly (#348) by Nick Krichevsky

* don't pass `--no-git` onto installers by Zach Daniel

* `modify_config_code` twice with keyword values (#332) by grzuy

## [v0.6.30](https://github.com/ash-project/igniter/compare/v0.6.29...v0.6.30) (2025-09-25)




### Bug Fixes:

* don't silently ignore certain errors during spinners by Zach Daniel

* don't display "temporarily adding igniter" when we aren't by Zach Daniel

## [v0.6.29](https://github.com/ash-project/igniter/compare/v0.6.28...v0.6.29) (2025-09-20)




### Bug Fixes:

* prevent duplicate 'live' directories for modules with Live namespace (#330) by Matthew Sinclair

* prevent duplicate 'live' directories for modules with Live namespace by Matthew Sinclair

### Improvements:

* add `delay_task` to run tasks at the end by Zach Daniel

## [v0.6.28](https://github.com/ash-project/igniter/compare/v0.6.27...v0.6.28) (2025-08-21)




### Bug Fixes:

* use appropriate function name `function` -> `function?` (#326) by Ciarán Walsh

### Improvements:

* `igniter.new` Don't run git init if already in git repo (#328) by Erik André Jakobsen

## [v0.6.27](https://github.com/ash-project/igniter/compare/v0.6.26...v0.6.27) (2025-08-14)


- releasing a new version to handle locally published version with IO.inspects left in 🤦‍♂️



## [v0.6.26](https://github.com/ash-project/igniter/compare/v0.6.25...v0.6.26) (2025-07-29)




### Bug Fixes:

* improve Phoenix web module detection in list_routers (#325) by James Harton

## [v0.6.25](https://github.com/ash-project/igniter/compare/v0.6.24...v0.6.25) (2025-07-23)




### Bug Fixes:

* remove another enumeration of the rewrite by Zach Daniel

## [v0.6.24](https://github.com/ash-project/igniter/compare/v0.6.23...v0.6.24) (2025-07-23)




### Bug Fixes:

* iterate over sources, not rewrite, in one more place by Zach Daniel

## [v0.6.23](https://github.com/ash-project/igniter/compare/v0.6.22...v0.6.23) (2025-07-23)




### Bug Fixes:

* remove case where we iterate a rewrite by Zach Daniel

## [v0.6.22](https://github.com/ash-project/igniter/compare/v0.6.21...v0.6.22) (2025-07-22)




### Bug Fixes:

* handle `:error` coming from alias updater by Zach Daniel

* add :error case clause in modify_existing_alias by Zach Daniel

## [v0.6.21](https://github.com/ash-project/igniter/compare/v0.6.20...v0.6.21) (2025-07-19)




### Bug Fixes:

* properly detect deps location by Zach Daniel

### Improvements:

* don't enumerate `igniter.rewrite` by Zach Daniel

## [v0.6.20](https://github.com/ash-project/igniter/compare/v0.6.19...v0.6.20) (2025-07-18)




### Bug Fixes:

* handle non-tty inputs on tasks that aren't installers by Zach Daniel

### Improvements:

* add a nicer error on `:eof` response from `yes?` by Zach Daniel

## [v0.6.19](https://github.com/ash-project/igniter/compare/v0.6.18...v0.6.19) (2025-07-15)




### Bug Fixes:

* typo in `set_yes` by Zach Daniel

## [v0.6.18](https://github.com/ash-project/igniter/compare/v0.6.17...v0.6.18) (2025-07-15)




### Improvements:

* support more tasks being called just from the archive by Zach Daniel

## `igniter.new` [v0.5.30](https://github.com/ash-project/igniter/compare/v0.6.16...v0.6.17) (2025-07-14)

### Features:

* create git repositories by default, and add `--no-git` to disable it

## [v0.6.17](https://github.com/ash-project/igniter/compare/v0.6.16...v0.6.17) (2025-07-14)




### Bug Fixes:

* properly use already retrieved task name by Zach Daniel

## [v0.6.16](https://github.com/ash-project/igniter/compare/v0.6.15...v0.6.16) (2025-07-14)




### Bug Fixes:

* remove all test macros by Zach Daniel

### Improvements:

* don't assume `--yes` with no tty when in test mode by Zach Daniel

* clean up and deprecate macros in `Igniter.Mix.Task` by Zach Daniel

* more granular info on the output of installers by Zach Daniel

## [v0.6.15](https://github.com/ash-project/igniter/compare/v0.6.14...v0.6.15) (2025-07-13)




### Bug Fixes:

* vendor `Path.relative_to` to get 1.18.4 behavior by Zach Daniel

* assume Kernel is imported in older Elixir versions by Zach Daniel

## [v0.6.14](https://github.com/ash-project/igniter/compare/v0.6.13...v0.6.14) (2025-07-09)




### Bug Fixes:

* a slew of fixes for config, code modification, deps addition, keywords by Zach Daniel

## [v0.6.13](https://github.com/ash-project/igniter/compare/v0.6.12...v0.6.13) (2025-07-09)




### Bug Fixes:

* handle unexpected cases around detecting tty by Zach Daniel

## [v0.6.12](https://github.com/ash-project/igniter/compare/v0.6.11...v0.6.12) (2025-07-09)




### Bug Fixes:

* properly encode values added to mix project by Zach Daniel

## [v0.6.11](https://github.com/ash-project/igniter/compare/v0.6.10...v0.6.11) (2025-07-06)




### Improvements:

* when stdin is not a tyy, treat that as --yes by Zach Daniel

## [v0.6.10](https://github.com/ash-project/igniter/compare/v0.6.9...v0.6.10) (2025-07-02)




### Improvements:

* make `Igniter.exists?` support directories by Zach Daniel

## [v0.6.9](https://github.com/ash-project/igniter/compare/v0.6.8...v0.6.9) (2025-06-25)




### Improvements:

* Implement removal of configuration (#309) by Benjamin Milde

* add `required?` option to `Igniter.update_elixir_file/3` by Benjamin Milde

## [v0.6.8](https://github.com/ash-project/igniter/compare/v0.6.7...v0.6.8) (2025-06-18)




### Bug Fixes:

* properly honor explicitly passed --only flag over other `only` configs by Zach Daniel

* properly render the child that must be placed in the supervision tree by Zach Daniel

### Improvements:

* Update argument error message about apply_igniter in test (#305) by Kenneth Kostrešević

## [v0.6.7](https://github.com/ash-project/igniter/compare/v0.6.6...v0.6.7) (2025-06-08)




### Bug Fixes:

* In assert_has_issue/3 set condition with issue as function #297 (#298)

### Improvements:

* fix issue w/ type system validation on old versions of elixir

* support private repositories

* Use hex to support looking up org package versions (#299)

* Add missing --only flag documentation for installer install task (#284)

* add `refute_creates`

## [v0.6.6](https://github.com/ash-project/igniter/compare/v0.6.5...v0.6.6) (2025-06-06)




### Improvements:

* remove protocol consolidation dev changes

* add `Igniter.rm` and track removed files across operations

## [v0.6.5](https://github.com/ash-project/igniter/compare/v0.6.4...v0.6.5) (2025-06-04)




### Bug Fixes:

* properly rename function & attributes on module move

## [v0.6.4](https://github.com/ash-project/igniter/compare/v0.6.3...v0.6.4) (2025-05-30)




### Bug Fixes:

* reword syntax to avoid compile error

### Improvements:

* introduce `Igniter.Scribe` and `--scribe` option

## [v0.6.3](https://github.com/ash-project/igniter/compare/v0.6.2...v0.6.3) (2025-05-29)




### Bug Fixes:

* display all error output, and bump installer version

* Display notices even when there are no content changes.

## [v0.6.2](https://github.com/ash-project/igniter/compare/v0.6.1...v0.6.2) (2025-05-24)




### Improvements:

* track task name and parent task name in igniter

* add `quiet_on_no_changes?` assign

* add usage-rules.md

## [v0.6.1](https://github.com/ash-project/igniter/compare/v0.6.0...v0.6.1) (2025-05-22)




### Bug Fixes:

* remove references to old versions

## [v0.6.0](https://github.com/ash-project/igniter/compare/v0.5.52...v0.6.0) (2025-05-21)




### Bug Fixes:

* OTP 28 Compatibility via removing inflex (#288)

Use `Igniter.Inflex.pluralize` or depend on `Inflex` directly if you need it

## [v0.5.52](https://github.com/ash-project/igniter/compare/v0.5.51...v0.5.52) (2025-05-20)




### Improvements:

* bump installer version

* Add igniter.init task to igniter_new archive (#283)

* clean up igniter after adding it for installation

* Task/adds move to function and attrs (#274)

* generate a test when generating a new task

## [v0.5.51](https://github.com/ash-project/igniter/compare/v0.5.50...v0.5.51) (2025-05-15)




### Bug Fixes:

* properly detect map format

* don't always create default config files

* Add impl to generated mix task (#276)

* Matches function guards when using move_to_def (#273)

## [v0.5.50](https://github.com/ash-project/igniter/compare/v0.5.49...v0.5.50) (2025-05-01)




### Bug Fixes:

* don't try to inspect functions in test helpers

## [v0.5.49](https://github.com/ash-project/igniter/compare/v0.5.48...v0.5.49) (2025-04-30)




### Improvements:

* properly honor `--only` flag

## [v0.5.48](https://github.com/ash-project/igniter/compare/v0.5.47...v0.5.48) (2025-04-29)




### Improvements:

* clean up `igniter/1-2` check, and make it a warning

## [v0.5.47](https://github.com/ash-project/igniter/compare/v0.5.46...v0.5.47) (2025-04-21)




### Improvements:

* make router optional in `select_endpoint`

* accept functions in warning/notice/issue assertions

* add `Igniter.Code.Common.variable?`

## [v0.5.46](https://github.com/ash-project/igniter/compare/v0.5.45...v0.5.46) (2025-04-15)




### Bug Fixes:

* wording in router selection message

## [v0.5.45](https://github.com/ash-project/igniter/compare/v0.5.44...v0.5.45) (2025-04-10)




### Bug Fixes:

* keep as close to installer order as possible for dependencies

## [v0.5.44](https://github.com/ash-project/igniter/compare/v0.5.43...v0.5.44) (2025-04-09)




### Bug Fixes:

* handle list of arities in `Igniter.Code.Function.function_call?/3`

### Improvements:

* install private packages from hexpm (#157)

* prevent infinitely looping install task

## [v0.5.43](https://github.com/ash-project/igniter/compare/v0.5.42...v0.5.43) (2025-04-02)




### Bug Fixes:

* properly use `dep_opts` when comparing new deps

## [v0.5.42](https://github.com/ash-project/igniter/compare/v0.5.41...v0.5.42) (2025-03-31)




### Improvements:

* add live_debugger to our known only env config

## [v0.5.41](https://github.com/ash-project/igniter/compare/v0.5.40...v0.6.0) (2025-03-28)




### Features:

* add igniter.add task (#258)

### Improvements:

* show warning about generating new umbrella projects

## [v0.5.40](https://github.com/ash-project/igniter/compare/v0.5.39...v0.5.40) (2025-03-26)




### Bug Fixes:

* only display changing sources in `puts_diff` in test

### Improvements:

* more testing helpers

* support error/warning/notice returns on updating files

## [v0.5.39](https://github.com/ash-project/igniter/compare/v0.5.38...v0.5.39) (2025-03-25)




### Bug Fixes:

* handler erlang style modules in function detection

* igniter.upgrade crash on dependency declaration when only option is an atom (#257)

### Improvements:

* add `Igniter.Code.Common.add_comment/2`

* add `Igniter.Project.Config.configure_group/6`

## [v0.5.38](https://github.com/ash-project/igniter/compare/v0.5.37...v0.5.38) (2025-03-21)




### Bug Fixes:

* handler erlang style modules in function detection

## [v0.5.37](https://github.com/ash-project/igniter/compare/v0.5.36...v0.5.37) (2025-03-18)




### Improvements:

* avoid duplicate module warning on local.igniter

## [v0.5.36](https://github.com/ash-project/igniter/compare/v0.5.35...v0.5.36) (2025-03-14)




### Bug Fixes:

* add in an ugly hack for handling common packages `only` option

## [v0.5.35](https://github.com/ash-project/igniter/compare/v0.5.34...v0.5.35) (2025-03-12)




### Bug Fixes:

* don't use `Application.app_dir` as the app may not be running yet

## [v0.5.34](https://github.com/ash-project/igniter/compare/v0.5.33...v0.5.34) (2025-03-12)




### Bug Fixes:

* ensure composed installers happen first

## [v0.5.33](https://github.com/ash-project/igniter/compare/v0.5.32...v0.5.33) (2025-03-11)




### Bug Fixes:

* add backwards compatibility function for relative_to_cwd

* trim package install list to handle edge case

* installer: handle `--with-args="string"` syntax

### Improvements:

* Add `:placement` option to `Phoenix.add_scope/4` and `Phoenix.append_to_scope/4` (#251)

* add `mix igniter.remove dep1 dep2` task

* add `assert_has_task` test helper

## [v0.5.32](https://github.com/ash-project/igniter/compare/v0.5.31...v0.5.32) (2025-03-08)




### Bug Fixes:

* properly replace `_` with `-` in task group names

## [v0.5.31](https://github.com/ash-project/igniter/compare/v0.5.30...v0.5.31) (2025-03-04)




## [v0.5.30](https://github.com/ash-project/igniter/compare/v0.5.29...v0.5.30) (2025-03-03)




### Bug Fixes:

* various fixes with cross project function renaming

* ensure all paths are relative_to_cwd

### Improvements:

* mix igniter.refactor.rename_function short doc (#243)

* add `local.igniter` task for easier upgrading

## [v0.5.29](https://github.com/ash-project/igniter/compare/v0.5.28...v0.5.29) (2025-02-25)




### Bug Fixes:

* remove erroneous diff displaying code

## [v0.5.28](https://github.com/ash-project/igniter/compare/v0.5.27...v0.5.28) (2025-02-24)




### Improvements:

* add phx_test_project for testing(#239)

## [v0.5.27](https://github.com/ash-project/igniter/compare/v0.5.26...v0.5.27) (2025-02-20)




### Improvements:

* support dep_opts in schema info

## [v0.5.26](https://github.com/ash-project/igniter/compare/v0.5.25...v0.5.26) (2025-02-20)




### Bug Fixes:

* only look for .formatter.exs files in known directories

* load all known archives when running the archive installer

## [v0.5.25](https://github.com/ash-project/igniter/compare/v0.5.24...v0.5.25) (2025-02-16)




### Bug Fixes:

* check file changed by actually comparing content

* pattern match error when default option is selected on long diff

## [v0.5.24](https://github.com/ash-project/igniter/compare/v0.5.23...v0.5.24) (2025-02-12)




### Bug Fixes:

* resolve project :config_path (#226)

## [v0.5.23](https://github.com/ash-project/igniter/compare/v0.5.22...v0.5.23) (2025-02-11)




### Bug Fixes:

* better error messages and fixes for unconventional deps

## [v0.5.22](https://github.com/ash-project/igniter/compare/v0.5.21...v0.5.22) (2025-02-11)




### Bug Fixes:

* fix & simplify keyword removal

* don't pass --from-elixir-install in with-args by default

* `web_module/1` duplicating Web (#221)

* ensure that installer includes apps igniter needs

* properly split --with-args

### Improvements:

* support non-literal/non-standard deps lists

* better UX around large files (#222)

* Change default updater fn for configure_runtime_env/6 to match configure/6 (#220)

## [v0.5.21](https://github.com/ash-project/igniter/compare/v0.5.20...v0.5.21) (2025-02-03)




### Bug Fixes:

* error in codemod while formatting

### Improvements:

* Add `:after` opt to `Config` functions (#213)

* make diff checking faster

## [v0.5.20](https://github.com/ash-project/igniter/compare/v0.5.19...v0.5.20) (2025-01-27)




### Improvements:

* raise when installing igniter as an archive

## [v0.5.19](https://github.com/ash-project/igniter/compare/v0.5.18...v0.5.19) (2025-01-27)




### Features:

* `Igniter.Code.Module.move_to_attribute_definition` (#207)

### Bug Fixes:

* handle single length list config paths that already exist

## [v0.5.18](https://github.com/ash-project/igniter/compare/v0.5.17...v0.5.18) (2025-01-27)




### Improvements:

* show yellow text indicating generated notices

## [v0.5.17](https://github.com/ash-project/igniter/compare/v0.5.16...v0.5.17) (2025-01-26)




### Improvements:

* remove warnings about `Phx.New` in some new projects

* properly parse with_args in igniter.new

## [v0.5.16](https://github.com/ash-project/igniter/compare/v0.5.15...v0.5.16) (2025-01-22)




### Improvements:

* add owl/inflex utility dependencies

## [v0.5.15](https://github.com/ash-project/igniter/compare/v0.5.14...v0.5.15) (2025-01-22)




### Improvements:

* protect against csv errors on windows

## [v0.5.14](https://github.com/ash-project/igniter/compare/v0.5.13...v0.5.14) (2025-01-21)




### Bug Fixes:

* ensure only relative paths are added to rewrite

## [v0.5.13](https://github.com/ash-project/igniter/compare/v0.5.12...v0.5.13) (2025-01-21)




### Bug Fixes:

* handle local igniter in installer w/ more granular deps compile

## [v0.5.12](https://github.com/ash-project/igniter/compare/v0.5.11...v0.5.12) (2025-01-20)




### Bug Fixes:

* don't run `deps.compile` task after `deps.get`

### Improvements:

* use `req` instead of httpc for calling to hex

* shorter package install line

## [v0.5.11](https://github.com/ash-project/igniter/compare/v0.5.10...v0.5.11) (2025-01-20)




### Bug Fixes:

* don't assume path for application module

## [v0.5.10](https://github.com/ash-project/igniter/compare/v0.5.9...v0.5.10) (2025-01-20)




### Bug Fixes:

* fix duplication of comments on dep writing in empty project

## [v0.5.9](https://github.com/ash-project/igniter/compare/v0.5.8...v0.5.9) (2025-01-19)




### Bug Fixes:

* combine comments when adding or replacing code

* `Igniter.Project.MixProject.update/4` now creates non-existing functions (#190)

### Improvements:

* ensure phoenix /live files go where they should

* Default `yes?` to Y (#197)

* Add `Phoenix.select_endpoint/3` (#192)

## [v0.5.8](https://github.com/ash-project/igniter/compare/v0.5.7...v0.5.8) (2025-01-06)




### Improvements:

* significant cleanup of deps compilation logic

* suppress all output for cleaner loading spinners

## [v0.5.7](https://github.com/ash-project/igniter/compare/v0.5.6...v0.5.7) (2025-01-06)




### Bug Fixes:

* properly iterate over tasks list

## [v0.5.6](https://github.com/ash-project/igniter/compare/v0.5.5...v0.5.6) (2025-01-05)




### Improvements:

* better step explanation in installer

## [v0.5.5](https://github.com/ash-project/igniter/compare/v0.5.4...v0.5.5) (2025-01-05)




### Bug Fixes:

* only display mix.exs changes when showing them

## [v0.5.4](https://github.com/ash-project/igniter/compare/v0.5.3...v0.5.4) (2025-01-05)




### Bug Fixes:

* don't show git warning for changes igniter made

* print message after diff

* allow check to pass when no issues found (#178)

### Improvements:

* capture and suppress output in installers (#186)

* print version diff when upgrading packages (#185)

* sort the `missing` packages when upgrading

## [v0.5.3](https://github.com/ash-project/igniter/compare/v0.5.2...v0.5.3) (2024-12-26)




### Bug Fixes:

* ensure deps are compiled and proceed w/ install if igniter is

### Improvements:

* rip out shared utils

## [v0.5.2](https://github.com/ash-project/igniter/compare/v0.5.1...v0.5.2) (2024-12-25)




### Improvements:

* add `--yes-to-deps` option to `mix igniter.install`

* add `--yes-to-deps` when using `mix igniter.new`

## [v0.5.1](https://github.com/ash-project/igniter/compare/v0.5.0...v0.5.1) (2024-12-24)




### Bug Fixes:

* Igniter.mkdir not expanding paths correctly (#174)

* handle case where third tuple elem is nil

* handle mix rebar deprecations for 1.18 (#172)

### Improvements:

* add `prepend_to_pipeline` and `has_pipeline` to

* add fallback igniter install in archive

## [v0.5.0](https://github.com/ash-project/igniter/compare/v0.4.8...v0.5.0) (2024-12-19)




### Features:

* add Igniter.mkdir (#165)

### Bug Fixes:

* set quoted default to handle regex escaping issues

* parse_argv callback should be overridable (#166)

* use original file's extname when moving files always

### Improvements:

* default igniter installation to being optional

* `Igniter.Project.MixProject.update/4` (#168)

* `Igniter.Project.MixProject.update/4`

* add `has_dep?/2`

* add convenient wrapper around installing new packages

## [v0.4.8](https://github.com/ash-project/igniter/compare/v0.4.7...v0.4.8) (2024-11-27)
### Breaking Changes:

* add `expand_env?` option to `Igniter.Code.Common.add_code/3` (#151)



### Bug Fixes:

* if alias elements are strings ensure they aren't interpreted as AST

* don't move modules back to their "proper" location

* use new `ignore_missing_sub_formatters` option in rewrite

### Improvements:

* add `:force?` option to `Igniter.Project.Application.add_new_child/3` (#156)

* handle io formatting more uniformly (#148)

* handle io formatting more uniformly

## [v0.4.7](https://github.com/ash-project/igniter/compare/v0.4.6...v0.4.7) (2024-11-12)

### Improvements:

- Add `Igniter.Libs.Swoosh` for working with Swoosh

### Bug Fixes:

- print a consistent number of blank lines around diffs (#147)

## [v0.4.6](https://github.com/ash-project/igniter/compare/v0.4.5...v0.4.6) (2024-11-06)

### Bug Fixes:

- suppress module conflict warning when running upgrade_igniter

- pass dot_formatter when updating rewrite sources (#144)

- skip unknown deps in dot formatter

### Improvements:

- Add `priv_dir` functions to return priv directory (#141)

## [v0.4.5](https://github.com/ash-project/igniter/compare/v0.4.4...v0.4.5) (2024-11-04)

### Bug Fixes:

- skip unknown deps in dot formatter

## [v0.4.4](https://github.com/ash-project/igniter/compare/v0.4.3...v0.4.4) (2024-11-03)

### Improvements:

- support replace_or_append instruction when modifying task aliases
- Add `priv_dir` functions to return priv directory (#141)

## [v0.4.3](https://github.com/ash-project/igniter/compare/v0.4.2...v0.4.3) (2024-11-02)

### Bug Fixes:

- various fixes for test formatting

### Improvements:

- Tools for removing formatter plugins & imported deps

## [v0.4.2](https://github.com/ash-project/igniter/compare/v0.4.1...v0.4.2) (2024-11-02)

### Bug Fixes:

- properly compose upgrade tasks

### Improvements:

- update rewrite to 1.0.0 (#135)

## [v0.4.1](https://github.com/ash-project/igniter/compare/v0.4.0...v0.4.1) (2024-11-01)

### Bug Fixes:

- apply 0.3 compatibility fixes for upgrades

## [v0.3.77](https://github.com/ash-project/igniter/compare/v0.3.76...v0.3.77) (2024-11-01)

### Bug Fixes:

- don't skip igniter composition on existing issues

- handle `Igniter.Project.Application.app_module/1` returning tuple

- properly retain trailing newlines in `replace_code/2`

- handle grouped options in positional args parsing

- properly pass --with-args to generator

- handle connected `=` in extract_positional_args

- properly split args on equals symbol

- `Igniter.Code.Common.replace_code/2`: Don't leave zipper at parent when extending blocks (#123)

### Improvements:

- Parse `argv` by default and store in `Igniter` struct (#131)

- upgrade `igniter/2` to `igniter/1` in simple cases

- optimize `Igniter.Project.Module.find_module/2` when all files haven't been loaded

- add `Igniter.Test.diff/2` (#120)

- add `Igniter.Test.diff/2`

## [v0.3.76](https://github.com/ash-project/igniter/compare/v0.3.75...v0.3.76) (2024-10-28)

### Bug Fixes:

- properly ignore `with-args` when passing args to installers

- `expand_literal` should expand single-child blocks

- `expand_literal` should return an error `Macro.expand_literals` doesn't return a literal

- make task run/1 overridable (#114)

- Support integer argument in `move_right/2` and `move_upwards/2` and add `move_left/2` (#113)

### Improvements:

- resolve project app names set using a module attribute (#111)

- resolve project app names set using a module attribute

## [v0.3.75](https://github.com/ash-project/igniter/compare/v0.3.74...v0.3.75) (2024-10-26)

### Bug Fixes:

- make update_gettext idempotent

## [v0.3.74](https://github.com/ash-project/igniter/compare/v0.3.73...v0.3.74) (2024-10-24)

### Bug Fixes:

- properly compare version lists

## [v0.3.73](https://github.com/ash-project/igniter/compare/v0.3.72...v0.3.73) (2024-10-24)

### Bug Fixes:

- don't use `yes?` if --git_ci or --yes

## [v0.3.72](https://github.com/ash-project/igniter/compare/v0.3.71...v0.3.72) (2024-10-22)

### Bug Fixes:

- set `--yes` automatically in git_ci

## [v0.3.71](https://github.com/ash-project/igniter/compare/v0.3.70...v0.3.71) (2024-10-22)

## [v0.3.70](https://github.com/ash-project/igniter/compare/v0.3.69...v0.3.70) (2024-10-22)

### Bug Fixes:

- properly upgrade deps with mix deps.update

## [v0.3.69](https://github.com/ash-project/igniter/compare/v0.3.68...v0.3.69) (2024-10-21)

### Improvements:

- add `mix igniter.refactor.unless_to_if_not`

## [v0.3.68](https://github.com/ash-project/igniter/compare/v0.3.67...v0.3.68) (2024-10-21)

### Bug Fixes:

- properly detect all version migrations

- make replacing code append to parent blocks when extendable

- pass through additional arguments to installers

- reintroduce accidentally removed function

- don't call into shared lib?

## [v0.3.67](https://github.com/ash-project/igniter/compare/v0.3.66...v0.3.67) (2024-10-19)

### Bug Fixes:

- ensure deps are always added in explicit tuple format

- don't use the 2 arg version of config when the first key would be ugly

## [v0.3.66](https://github.com/ash-project/igniter/compare/v0.3.65...v0.3.66) (2024-10-19)

### Improvements:

- significant improvements to function checking speed

## [v0.3.65](https://github.com/ash-project/igniter/compare/v0.3.64...v0.3.65) (2024-10-19)

### Improvements:

- add `mix igniter.upgrade`

- add `mix igniter.refactor.rename_function`

## [v0.3.64](https://github.com/ash-project/igniter/compare/v0.3.63...v0.3.64) (2024-10-17)

### Bug Fixes:

- don't infinitely recurse on update_all_matches

- detect node removal in update_all_matches

### Improvements:

- add `Igniter.Code.String`

## [v0.3.63](https://github.com/ash-project/igniter/compare/v0.3.62...v0.3.63) (2024-10-15)

### Bug Fixes:

- properly collect csv options into lists

## [v0.3.62](https://github.com/ash-project/igniter/compare/v0.3.61...v0.3.62) (2024-10-14)

### Bug Fixes:

- properly parse csv/keep options

## [v0.3.61](https://github.com/ash-project/igniter/compare/v0.3.60...v0.3.61) (2024-10-14)

### Improvements:

- support csv option type and properly handle keep options lists

## [v0.3.60](https://github.com/ash-project/igniter/compare/v0.3.59...v0.3.60) (2024-10-14)

### Improvements:

- don't rely on elixir 1.16+ features

## [v0.3.59](https://github.com/ash-project/igniter/compare/v0.3.58...v0.3.59) (2024-10-14)

### Bug Fixes:

- don't return igniter from message function

## [v0.3.58](https://github.com/ash-project/igniter/compare/v0.3.57...v0.3.58) (2024-10-13)

### Bug Fixes:

- don't assume the availabilit of `which`

## [v0.3.57](https://github.com/ash-project/igniter/compare/v0.3.56...v0.3.57) (2024-10-11)

### Improvements:

- add `group` and option disambiguation based on groups

## [v0.3.56](https://github.com/ash-project/igniter/compare/v0.3.55...v0.3.56) (2024-10-11)

### Improvements:

- support required arguments in the info schema

## [v0.3.55](https://github.com/ash-project/igniter/compare/v0.3.54...v0.3.55) (2024-10-11)

### Bug Fixes:

- fix pattern match on prompt on git changes

## [v0.3.54](https://github.com/ash-project/igniter/compare/v0.3.53...v0.3.54) (2024-10-11)

### Bug Fixes:

- looser match on git change detection

## [v0.3.53](https://github.com/ash-project/igniter/compare/v0.3.52...v0.3.53) (2024-10-11)

### Improvements:

- add `on_exists` handling to `Igniter.Libs.Ecto.gen_migration`

## [v0.3.52](https://github.com/ash-project/igniter/compare/v0.3.51...v0.3.52) (2024-10-07)

### Improvements:

- properly warn on git changes before committing

## [v0.3.51](https://github.com/ash-project/igniter/compare/v0.3.50...v0.3.51) (2024-10-07)

### Bug Fixes:

- provide proper version in the installer

### Improvements:

- remove `System.cmd` for `igniter.install` in installer

- allow excluding line numbers in `Igniter.Test.assert_has_patch`

- prettier errors on task exits

## [v0.3.50](https://github.com/ash-project/igniter/compare/v0.3.49...v0.3.50) (2024-10-07)

### Improvements:

- don't warn on missing installers that aren't actually missing

## [v0.3.49](https://github.com/ash-project/igniter/compare/v0.3.48...v0.3.49) (2024-10-06)

### Bug Fixes:

- fix dialyzer spec

## [v0.3.48](https://github.com/ash-project/igniter/compare/v0.3.47...v0.3.48) (2024-10-04)

### Improvements:

- add `opts_updater` option to `add_new_child`

- add `Igniter.Libs.Ecto.gen_migration`

- implement various deprecations

- add `Igniter.Libs.Ecto` for listing/selecting repos

- add `defaults` key to `Info{}`

## [v0.3.47](https://github.com/ash-project/igniter/compare/v0.3.46...v0.3.47) (2024-10-04)

### Bug Fixes:

- prompt users to handle diverged environment issues

- display installer output in `IO.stream()`

- honor --yes properly when adding nested deps

- don't install revoked versions of packages

- install non-rc packages, or the rc package if there is none

## [v0.3.46](https://github.com/ash-project/igniter/compare/v0.3.45...v0.3.46) (2024-10-03)

### Bug Fixes:

- fix message in task name warning

## [v0.3.45](https://github.com/ash-project/igniter/compare/v0.3.44...v0.3.45) (2024-09-25)

### Bug Fixes:

- use `ensure_all_started` without a list for backwards compatibility

### Improvements:

- Yn -> y/n to represent a lack of a default

## [v0.3.44](https://github.com/ash-project/igniter/compare/v0.3.43...v0.3.44) (2024-09-24)

### Bug Fixes:

- properly create or update config files

- format files after reading so formatter_opts is set before later writes

- remove incorrect call to `add_code` from `replace_code`

## [v0.3.43](https://github.com/ash-project/igniter/compare/v0.3.42...v0.3.43) (2024-09-23)

### Bug Fixes:

- traverse lists without entering child nodes

## [v0.3.42](https://github.com/ash-project/igniter/compare/v0.3.41...v0.3.42) (2024-09-23)

### Bug Fixes:

- handle empty requested positional args when extracting positional

### Improvements:

- add `Igniter.Code.List.replace_in_list/3`

- allow appending/prepending a different value when the full

## [v0.3.41](https://github.com/ash-project/igniter/compare/v0.3.40...v0.3.41) (2024-09-23)

### Improvements:

- add `Igniter.Project.TaskAliases.add_alias/3-4`

## [v0.3.40](https://github.com/ash-project/igniter/compare/v0.3.39...v0.3.40) (2024-09-23)

### Bug Fixes:

- properly detect existing scopes with matching names

## [v0.3.39](https://github.com/ash-project/igniter/compare/v0.3.38...v0.3.39) (2024-09-18)

### Bug Fixes:

- don't warn while parsing files

- display an error when a composed task can't be found

### Improvements:

- more phoenix router specific code

- make `issues` red and formatted with more spacing

- properly compare regex literals

- add `dont_move_file_pattern` utility

- update installer to always run mix deps get and install

## [v0.3.38](https://github.com/ash-project/igniter/compare/v0.3.37...v0.3.38) (2024-09-16)

### Bug Fixes:

- don't add warning on `overwrite` option

### Improvements:

- better confirmation message experience

## [v0.3.37](https://github.com/ash-project/igniter/compare/v0.3.36...v0.3.37) (2024-09-15)

### Improvements:

- return `igniter` in `Igniter.Test.assert_unchanged`

## [v0.3.36](https://github.com/ash-project/igniter/compare/v0.3.35...v0.3.36) (2024-09-13)

### Bug Fixes:

- reevaluate .igniter.exs when it changes

### Improvements:

- Support for extensions in igniter config

- Add a phoenix extension to prevent moving modules that may be phoenix-y

## [v0.3.35](https://github.com/ash-project/igniter/compare/v0.3.34...v0.3.35) (2024-09-10)

### Bug Fixes:

- much smarter removal of `import_config` when evaluating configuration files

- when including a glob, use `test_files` in test_mode

### Improvements:

- add `Igniter.Code.Common.remove/2`

## [v0.3.34](https://github.com/ash-project/igniter/compare/v0.3.33...v0.3.34) (2024-09-10)

### Bug Fixes:

- properly avoid adding duplicate children to application tree

## [v0.3.33](https://github.com/ash-project/igniter/compare/v0.3.32...v0.3.33) (2024-09-10)

### Bug Fixes:

- properly determine module placement in app tree

## [v0.3.32](https://github.com/ash-project/igniter/compare/v0.3.31...v0.3.32) (2024-09-10)

### Bug Fixes:

- properly extract app module from `def project`

## [v0.3.31](https://github.com/ash-project/igniter/compare/v0.3.30...v0.3.31) (2024-09-10)

### Bug Fixes:

- set only option to `nil` by default

## [v0.3.30](https://github.com/ash-project/igniter/compare/v0.3.29...v0.3.30) (2024-09-10)

### Bug Fixes:

- handle some edge cases in application child adding

### Improvements:

- support the opts being code when adding a new child to the app tree

- prepend new children instead of appending them

- add an `after` option to `add_new_child/3`

- better warnings on invalid patches in test

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

- move project related things to `Project` namespace

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
