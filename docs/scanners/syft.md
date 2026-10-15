# Syft

SBOM generator. Produces a CycloneDX document listing every package in a directory or image,
with versions, licences and package URLs, for Dependency-Track.

## Where it runs

Pipeline stage 5, `syft dir:. -o cyclonedx-json`, right after the dependency scan. The
Jenkins Dependency-Track plugin uploads the file. Generate the SBOM from the final image
as well (`syft <host>:5000/app:42`) when the deployment artifact is the image, because
that is what runs in production.

## Commands

```bash
syft dir:. -o cyclonedx-json > sbom.cdx.json
syft <host>:5000/app:42 -o cyclonedx-json > image-sbom.cdx.json
syft dir:. -o spdx-json > sbom.spdx.json       # if a client asks for SPDX
syft dir:. -o table                             # human readable
```

## Configuration

`.syft.yaml` in the repository or `SYFT_*` environment variables. Relevant settings:
exclude paths (`exclude: ["./tests/**"]`), cataloger selection (keep `php-composer-lock`,
`javascript-lock`, `dpkg`, `apk`), and `package.search-unindexed-archives` for vendored jars.

Syft reads lock files and installed package metadata; it does not resolve dependencies, so the
SBOM reflects what was installed, which is what you want.

## Why SBOMs matter here

Clients increasingly need to answer "are we affected" within hours of a disclosure, and some
regulations and procurement processes now ask for an SBOM per release. Dependency-Track keeps
every version's SBOM, so the answer is a search rather than a rebuild. Keep the SBOM as a build
artifact next to the image as well, signed later with cosign if the client goes that far.

## Free edition and limits

Apache 2.0, maintained by Anchore, no paid edition. Licence detection is best effort; packages
without licence metadata show as unknown and need manual review in Dependency-Track.
