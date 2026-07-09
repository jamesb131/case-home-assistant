# Private GitHub repos and CASE packages

CASE currently uses a GitHub add-on repository plus prebuilt GHCR images:

```text
GitHub repository -> Home Assistant add-on metadata
GHCR packages     -> case-core and case-postgres container images
```

Making the source private is sensible, but Home Assistant still needs a way to
read the add-on metadata and pull the images.

## Recommended staged approach

Use this order:

1. Keep the add-on repo public until the HTTPS and phone path is stable.
2. Keep GHCR images public, but with no secrets baked into them.
3. Once stable, make the source repo private.
4. If desired later, make GHCR packages private too and add registry auth.

This keeps HA updates simple while removing the application source from public
view.

## Before making the repo private

Confirm:

- Google auth files are ignored and live only in `/share/case/google` or
  `/data/google`.
- CASE API tokens are set through Home Assistant add-on options, not committed.
- The GitHub Actions workflow can still publish GHCR images.
- The Green can install/update CASE from the current add-on repository.

## If the add-on repo becomes private

Home Assistant needs credentials to clone the add-on repository. The practical
options are:

- Add the repository with a GitHub token embedded in the repository URL.
- Keep a tiny public packaging repository that points at prebuilt GHCR images.

The tiny public packaging repository is usually less brittle. It contains only:

```text
repository.yaml
case_core/config.yaml
case_core/README.md
case_core/DOCS.md
case_core/translations/en.yaml
case_postgres/config.yaml
case_postgres/README.md
case_postgres/DOCS.md
case_postgres/translations/en.yaml
```

The private app repository keeps the real source, Dockerfiles, workflows and
development history.

## GHCR package visibility

If GHCR packages stay public, HA can pull images without registry credentials.
That is the easiest secure-enough setup because images should not contain
secrets.

If GHCR packages are private, HA also needs registry credentials. Do this only
after the split is stable, because private package pulls add another failure
point during add-on updates.

## Personal access tokens

Use separate tokens for separate jobs:

- Build/publish token: `write:packages`, used only by GitHub Actions if
  `GITHUB_TOKEN` cannot publish packages.
- HA read token: read-only repository access, used only by Home Assistant if the
  add-on metadata repo is private.

Do not reuse either token for day-to-day development.

