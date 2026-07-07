# CASE Postgres

Install this app before CASE Core.

For a local add-on install, other add-ons can reach this database at:

```text
local-case-postgres:5432
```

Use the same database credentials in CASE Core's options.

The image is expected to be built and published separately as:

```text
ghcr.io/jamesb131/case-home-assistant/case-postgres:<config version>
```

Postgres data should live in:

```text
/data/postgres
```
