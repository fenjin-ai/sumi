# Bundled Typst packages

These unmodified package archives are redistributed from the official Typst package registry to make the Sumi welcome guide and existing Code notes documents work without a first-use download. Imports stay explicit and version-pinned in exported Typst source. Runtime files and upstream license notices are preserved.

| Package | Registry archive | SHA-256 |
| --- | --- | --- |
| codly 1.3.0 | https://packages.typst.org/preview/codly-1.3.0.tar.gz | `355a8afca97ec28b23110fe1fa1d33dcc98d99ef8b93fc1a29e2ec2c78a6f6cb` |
| codly-languages 0.1.1 | https://packages.typst.org/preview/codly-languages-0.1.1.tar.gz | `8e7f59a10b0d55ee7bcdf85e73ebb2da242e7cf93915fcf88f35b0c2f93d16bf` |
| cetz 0.5.2 | https://packages.typst.org/preview/cetz-0.5.2.tar.gz | `77cf8490114ae04c6e665a11efa691d284a0cadb9719771b5708c1197292f23f` |
| oxifmt 1.0.0 (CeTZ dependency) | https://packages.typst.org/preview/oxifmt-1.0.0.tar.gz | `7d17a1fc8ad01740ec3cb2b03c7360a4225ff9318e5710765fa98ea6fd59594f` |

Codly and codly-languages use MIT; CeTZ uses LGPL-3.0-or-later; oxifmt offers MIT OR Apache-2.0. See each package's LICENSE file. Package data is copied atomically into Sumi's private package cache on service startup. Existing documents do not acquire hidden imports, and upgrading Sumi does not silently change an existing document's package version.

CeTZ is distributed as unmodified, editable `.typ` source, not linked into the application executable. Its complete registry sources and license are included. Source projects retain explicit imports; users can replace the package in their package cache or change the import. Original registry archives can be retrieved from the URLs above. Sumi's original example prose, drawing and code are not copied from upstream examples.
