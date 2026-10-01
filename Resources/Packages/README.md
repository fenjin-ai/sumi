# Bundled Typst packages

These unmodified package archives are redistributed from the official Typst package registry to make the Code notes template work without a first-use download. Imports stay explicit and version-pinned in exported Typst source. Runtime files and upstream license notices are preserved.

| Package | Registry archive | SHA-256 |
| --- | --- | --- |
| codly 1.3.0 | https://packages.typst.org/preview/codly-1.3.0.tar.gz | `355a8afca97ec28b23110fe1fa1d33dcc98d99ef8b93fc1a29e2ec2c78a6f6cb` |
| codly-languages 0.1.1 | https://packages.typst.org/preview/codly-languages-0.1.1.tar.gz | `8e7f59a10b0d55ee7bcdf85e73ebb2da242e7cf93915fcf88f35b0c2f93d16bf` |

Both use the MIT License; see each package's LICENSE file. Package data is copied atomically into Sumi's private package cache on service startup. Existing documents do not acquire hidden imports, and upgrading Sumi does not silently change an existing document's package version.
