# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

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
