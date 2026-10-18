# Default configuration file for FileBrowser Quantum

**Status:** approved
**Date:** 2026-10-18
**Scope:** `config/config.yaml`, `Dockerfile`, `run/nobody/start.sh`

## Problem

The image ships no configuration seed. `run/nobody/start.sh` runs FileBrowser with
`--config /config/filebrowser/config/config.yaml`, so a fresh container has no config file at that path
until the user writes one, and the operator has no in-repo reference describing which options exist.

The repo currently holds a partial, hand-written draft at `config/config.yaml` (3.5 KB): it covers
`http.port`, `server.sources`, `auth.adminUsername`, `auth.methods.password.minLength` and a handful of
commented examples. It is neither complete nor wired into the build, and its `sources[].path` is `/data`
while this image mounts files at `/media`.

## Goals

1. Provide one complete, commented reference file at `config/config.yaml` listing every option supported
   by the FileBrowser release this image installs, so an operator can uncomment what they need.
2. Keep only a small "basic configuration" active, so the file boots a working instance out of the box.
3. Seed that file into a fresh container automatically, without ever overwriting an existing config.
4. Keep the existing effective config location working for installs created before this change.

## Non-goals

- No change to `install.sh`, the Unraid template XML, `.gitignore`, or git initialisation.
- No README rewrite. The README documents `ENABLE_TLS`, `ENABLE_AUTHENTICATION`, `FILEBROWSER_ROOT` and
  healthcheck variables that `start.sh` does not implement, and states default credentials of
  `admin/filebrowser` where v2.0.1 defaults to `admin/admin`. Both are known inaccuracies, recorded here
  and left untouched.
- No runtime config-generation logic, templating, or environment-variable substitution.
- No change to how secrets are supplied; environment variables keep working exactly as today.

## Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Runtime role of the file | Bundle in the image and seed on first run | The user asked for the file to actually be used, not just documented |
| Option surface version | Match the installed release, `v2.0.1-stable` | Config validation rejects unknown keys, so keys from a newer release would break startup when uncommented |
| Active settings | Container-aware basics | Only `/config` is persisted, so database, cache and config should live there |
| Secrets | All commented, with env-var notes | A config-file `adminPassword` is re-applied on every start and would reset a changed password |
| Existing draft | Replaced wholesale | Guarantees complete coverage and no stale keys |
| Authoring method | Hand-authored curated reference | The file's purpose is human guidance; readability beats mechanical fidelity |
| Seed target path | `/config/config.yaml` (flattened) | Mirrors the repo layout and is easier to find on the host |
| Seeding mechanism | Copy from `/opt` at first run | A baked file at `/config/...` is hidden by the bind mount |

## File content design

### Upstream pin

The image's `build/root/install.sh` downloads the latest GitHub release
(`gh.sh --github-owner gtsteffaniak --github-repo filebrowser --download-type release ...`), which at the
time of writing is `v2.0.1-stable` (published 2026-10-13). The authoritative option list for that release
is `frontend/public/config.generated.yaml` at that tag. The docs site tracks a newer branch and is used
only for prose explanations, not as the key list.

The v2.0.1 and main-branch surfaces differ materially, which is why the pin matters:

- `auth.adminUsername` and `auth.adminPassword` sit at `auth:` level in v2.0.1 and moved under
  `auth.methods.password:` on main.
- `server.searchResultsLimit`, `server.database.quotas`, `shareDefaults`, `userDefaults.account.showAdvancedProfile`,
  `userDefaults.listing.promptRightCloseButton`, `userDefaults.listing.newFileTemplate`,
  `userDefaults.listing.showTypeColumn` and `userDefaults.listing.showCreationDateColumn` exist only on main.
- `userDefaults.fileViewer.editorQuickSave` exists only in v2.0.1.

### Header banner

The file opens with a comment block stating: this is the reference configuration for the image; only the
basic settings are active and the rest must be uncommented; unknown keys are rejected at startup; upstream
version `v2.0.1-stable`; the `config.generated.yaml` URL at that tag; the docs URL; and a note that every
secret key has a matching `FILEBROWSER_*` environment variable which the container already exports.

### Ordering and section banners

Keys are ordered to mirror the upstream generated file: `server`, `auth`, `frontend`, `userDefaults`,
`integrations`, `http`. This keeps a future version sync a straight diff instead of a reshuffle.

Each group opens with a short comment banner naming what it controls and linking its docs page
(`/docs/configuration/server/`, `/docs/configuration/http/`, `/docs/configuration/authentication/`,
`/docs/configuration/users/`, `/docs/configuration/frontend/`). `server.logging` has no group of its own,
so its banner sits inside the `server` block and links `/docs/configuration/logging/`.

### Active block

Exactly the keys below are uncommented. They are shown grouped for readability; in the file they sit in
their upstream positions, and each active key replaces its commented counterpart so no key is documented
twice.

```yaml
http:
  port: 8125

server:
  sources:
    - path: "/media"
      name: "Media"
      config:
        defaultEnabled: true
  cacheDir: "/config/filebrowser/cache"
  database:
    path: "/config/filebrowser/database.sqlite"

auth:
  methods:
    password:
      enabled: true
      minLength: 8
```

`port: 8125` matches the webui port in the README and the published template. `/media` is the files bind
mount. `cacheDir` holds previews, the search index (`cacheDir/sql`) and archive temporaries;
`database.path` holds users, shares and activity. Both must be under `/config` to survive container
recreation.

### Commented surface

Every leaf key in the v2.0.1 reference is present, verified mechanically (see Verification). That includes
`server.sources[].config.rules[]` with all 13 rule keys, `server.indexSqlConfig`, `server.database.activity`,
the full `auth.methods.{proxy,oidc,ldap,jwt,passkey}` trees plus `auth.noauth`, all eight `userDefaults`
sub-groups, `integrations.office`, and both `integrations.media.convert` format matrices.

Keys keep a short trailing comment in the upstream style so behaviour is discoverable without opening the
docs. Upstream's placeholder examples (`(untracked)`, `help prompt`, `/relative/or/absolute/path`,
`"Source Name"`) are replaced with commented, realistic examples for this container.

### Secrets

`auth.adminUsername`, `auth.adminPassword`, `auth.key`, `auth.totpSecret`, `auth.methods.oidc.clientSecret`,
`auth.methods.ldap.userPassword`, `auth.methods.jwt.secret`, `auth.methods.password.recaptcha.secret` and
`integrations.office.secret` stay commented, each with a note naming the matching `FILEBROWSER_*` variable.
For `auth.adminPassword` the note states explicitly that a value here is re-applied on every start.

## Wiring design

### Dockerfile

One line is added alongside the existing `ADD` statements:

```dockerfile
# add default configuration seed
ADD config/config.yaml /opt/filebrowser/config.default.yaml
```

`ADD` creates `/opt/filebrowser` before `RUN install.sh` executes, and `install.sh`'s existing
`chmod -R 775 /opt/filebrowser` applies to the seed.

### start.sh

The path block and the exec line change; the environment exports and `ADDITIONAL_PARAMETERS` handling stay
as they are.

1. Paths: `config_file=/config/config.yaml`, `seed_config_file=/opt/filebrowser/config.default.yaml`,
   `legacy_config_file=/config/filebrowser/config/config.yaml`, `data_root=/config/filebrowser`.
2. Data directory: keep `mkdir -p "${data_root}"` so `cacheDir` and `database.path` have a parent.
3. Seed once, in this order:
   - `config_file` exists: use it, log nothing.
   - Else `legacy_config_file` exists: copy it to `config_file`, log that the legacy config was migrated.
   - Else `seed_config_file` exists: copy it to `config_file`, log that the default config was seeded.
   - Else: log `[crit]` and exit non-zero.
   The copy preserves the source file's mode; ownership follows the container user that runs `start.sh`.
   Never overwrite an existing `config_file`. If a legacy file coexists with the new one, log that the
   legacy file is ignored.
4. Exec: `--config "${config_file}"`, with `${ADDITIONAL_PARAMETERS}` unchanged.

### Behaviour matrix

| Scenario | Result |
| --- | --- |
| Fresh container, empty `/config` | Seed copied to `/config/config.yaml`, edit survives restarts |
| Install predating this change | Legacy config copied to `/config/config.yaml`, container behaviour unchanged |
| Legacy config coexisting with a new config | New config used, legacy ignored and logged |
| Operator deletes `/config/config.yaml` | Re-seeded on next start |
| Seed missing from image (bad build) and no config | `[crit]` exit, no silent restart loop |

## Error handling

`start.sh` does not use `set -e`, so each branch is explicit:

- `/config` missing: existing `[crit]` guard, unchanged.
- `/config` present but not writable by the container user, or the copy fails: `[crit]` message, exit non-zero.
- No config and no seed: `[crit]` message naming both paths, exit non-zero.
- An invalid config is rejected by FileBrowser's own validation at startup, which is the intended final guard.

## Verification

Temp scripts live in `/tmp`, never in the repo.

| Check | Method | Pass condition |
| --- | --- | --- |
| YAML parses | `python3` with `yaml.safe_load` on `config/config.yaml` | no exception |
| Active surface is exactly the basics | parse, walk key paths, compare with the eight intended active paths | no uncommented key outside the list |
| Full option coverage | extract leaf key paths from `config.generated.yaml` at `v2.0.1-stable`, search the raw file text for each | zero missing keys |
| No live secrets | grep for uncommented `adminPassword`, `auth.key`, `totpSecret`, `clientSecret`, `userPassword`, `secret` | no hits |
| Shell lint | `shellcheck run/nobody/start.sh` | clean |
| Markdown lint | `markdownlint --fix` on this spec | no non-table line above the project's 120-character limit; default-80 MD013 warnings accepted |
| Seed behaviour | with Docker available: build, run against an empty `/config`, assert the file appears and matches the seed; edit it, restart, assert no overwrite; pre-place a legacy config, assert the migration branch | all branches behave as in the matrix |
| Existing-install safety | diff old and new `start.sh` | only config path handling differs; env exports untouched |

Docker-based checks are reported as **not run** when Docker is unavailable; they are never reported as
passing.

## Risks and trade-offs

- **`database.path` versus `FILEBROWSER_DATABASE_PATH`.** An active `server.database.path` takes precedence
  over the environment variable, so an operator relying on that variable must delete the key. The file
  says so inline.
- **Persisted cache growth.** `cacheDir` now lives on the persisted volume; `cacheDirCleanup` is shown
  commented beside it as the mitigation.
- **Seed updates only reach fresh installs.** Editing the seed in a later release never touches an
  existing deployment. Stated in the header banner.
- **Version skew on upgrade.** When `install.sh` starts pulling a release whose schema differs (for example
  once v2.1.x becomes the latest release), the pinned header and the `auth.adminUsername` placement become
  stale and the file must be re-synced.
- **Flattened config path.** Moving `--config` from `/config/filebrowser/config/config.yaml` to
  `/config/config.yaml` is why the legacy migration branch exists; skipping it would silently reset
  existing deployments to the seed.

## Rollback

Revert the `Dockerfile` line and the `start.sh` blocks; restore the previous `config/config.yaml`. A
container started with the new file keeps working with the old script because the legacy migration branch
copies rather than moves, so both paths remain populated.
