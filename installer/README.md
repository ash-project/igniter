## mix igniter.new

Provides `igniter.new` installer as an archive.

To install from Hex, run:

```shell
$ mix archive.install hex igniter_new
```

To build and install it locally, ensure the previous version is removed prior to installation:

```shell
$ cd installer
$ mix archive.uninstall igniter_new
$ MIX_ENV=prod mix do archive.build + archive.install
```
