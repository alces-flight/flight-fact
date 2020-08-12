# Flight Fact

Manage Alces Flight Center Metedata

## Overview

Update metadata entries associated with an Alces Flight Center Asset

## Installation

The application requires a modern(ish) version of `ruby`/`bundler`. It has been designed with the following versions in mind:
* centos7
* ruby 2.7.1
* bundler 2.1.4

After downloading the source code (via git or other means), the gems need to be installed using bundler:

```
cd /path/to/source
bundle install --with default --without development --path vendor
```

## Configuration

The application can be used in one of two ways:
* Configured against a default asset, or
* Update other asset metadata entries

The tool will automatically pick up `flight-asset` if it has been installed in the standard location.
See [reference config](etc/config.reference) on how to update the base config for non-standard installs.

The `flight-asset` utility is used to provide multi-asset support. It needs to be configured independently to this application.

Optionally a default asset can be set for the application. This removes the need to provide the `--asset` flag with each request.

The `configure` command will step you through setting the API access token and default asset:

```
$ bin/fact configure
Alces Flight Center API token: ************************
Define the default asset by ID? No
Define the default asset by name? Yes
Default Asset Name:
```

## Operation

See the help text for the main commands list:

```
bin/fact --help
```

To update, view, and delete metadata entries for the default asset:

```
# Set the metadata entries
$ bin/fact set foo bar
$ bin/fact set baz fiz

# View all the metadata entries
$ bin/fact list
baz: fiz
foo: bar

# View an individual entry
$ bin/fact get foo
bar

# Delete an entry
$ bin/fact delete baz
```

With the `flight-asset` support all the above commands can be ran on a different asset. This is done by providing the `--asset` flag:

```
# View all the metadata entries for a different asset
$ bin/fact list --asset different-node
...
```

# Known Issues

Even though `flight-fact` and `flight-asset` share the same larger API, they are configured independently. This can lead to also sorts of idiosyncrasies between the two application including:
 * The default asset works fine but `--asset` is broken. This is likely due to `flight-asset` having an expired token.
 * Super weirdness if the `base_url` is different between `flight-fact` and `flight-asset`. This would likely break `--asset` with a cryptic internal error as `flight-fact` will incorrectly resolve names to IDs.

# Contributing

Fork the project. Make your feature addition or bug fix. Send a pull
request. Bonus points for topic branches.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

# Copyright and License

Eclipse Public License 2.0, see [LICENSE.txt](LICENSE.txt) for details.

Copyright (C) 2019-present Alces Flight Ltd.

This program and the accompanying materials are made available under
the terms of the Eclipse Public License 2.0 which is available at
[https://www.eclipse.org/legal/epl-2.0](https://www.eclipse.org/legal/epl-2.0),
or alternative license terms made available by Alces Flight Ltd -
please direct inquiries about licensing to
[licensing@alces-flight.com](mailto:licensing@alces-flight.com).

Flight Asset is distributed in the hope that it will be
useful, but WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER
EXPRESS OR IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR
CONDITIONS OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR
A PARTICULAR PURPOSE. See the [Eclipse Public License 2.0](https://opensource.org/licenses/EPL-2.0) for more
details.
