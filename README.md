# theseus

Phase 1 of the DRS v1 → v2 migration tool: one v1 pid in, one v2 resource out.
The design is `gap_reports/theseus_phase_1_design.md`.

## Setup

Theseus runs on Ruby 3.4.10 (see `.ruby-version`).

```
bundle install
cp .env.example .env    # then fill it in
```

## Commands

```
bin/theseus lookup neu:xyz                # the v1 chain from neu:xyz up to neu:1
bin/theseus export neu:xyz                # neu:xyz's v1 MODS, to stdout
bin/theseus import neu:xyz                # create neu:xyz, and missing ancestors, in v2
bin/theseus import neu:xyz --into <noid>  # create neu:xyz only, under <noid>
```

`import` sends each v1 pid to Atlas, so Cerberus redirects the v1 URL with no
load step. It asks Atlas which ancestors v2 already has, and starts from the
object Atlas holds for `neu:1`. Each run adds rows to `runs/import_log.csv`
and keeps the exported MODS in `runs/mods/`.

Exit status: 0 success, 1 usage, 2 configuration, 3 v1 refused the request,
4 a finding about the v1 record, 5 a v2 failure.

## Tests

```
bundle exec rspec
```

The specs stub every HTTP call. None reaches v1 or Atlas.
