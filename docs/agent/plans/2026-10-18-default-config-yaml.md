# Default FileBrowser Quantum Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use sub-agents (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a complete commented `config/config.yaml` for v2.0.1-stable, seeded on first start
without overwriting an existing config.

**Architecture:** One hand-authored YAML file replacing the partial draft, pinned to the upstream tag that
`build/root/install.sh` downloads. The Dockerfile bundles it at `/opt/filebrowser/config.default.yaml`;
`run/nobody/start.sh` copies it (or migrates a pre-existing legacy config) to `/config/config.yaml`
before exec'ing the binary with `--config`. Only eight key paths stay active; everything else is commented.

**Tech Stack:** YAML (FileBrowser Quantum v2.0.1-stable schema), Bash (shellcheck-clean),
Docker (binhex arch-base image), Python 3 + PyYAML for verification scripts kept in `/tmp`.

---

## Scope check

The spec (`docs/agent/specs/2026-10-18-default-config-yaml-design.md`) covers a single subsystem:
one config artefact plus the two files needed to seed it. No decomposition required.

## File structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `config/config.yaml` | Replace | The reference config: header banner, six section banners, eight active keys, every other v2.0.1 key commented |
| `Dockerfile` | Modify | Bundle the seed at `/opt/filebrowser/config.default.yaml` |
| `run/nobody/start.sh` | Modify | Resolve paths, create data dir, seed/migrate config once, exec with `--config` |
| `/tmp/*` | Create (not committed) | Reference snapshot, checker, seeding simulator, baseline copies |

No new repo files. `README.md`, `build/root/install.sh` and the Unraid template are explicitly out of
scope per the spec's non-goals.

## Baseline facts the implementer needs

- Upstream reference for the pinned tag:
  `https://raw.githubusercontent.com/gtsteffaniak/filebrowser/v2.0.1-stable/frontend/public/config.generated.yaml`
- In v2.0.1 `auth.adminUsername` and `auth.adminPassword` are **direct children of `auth:`** — not under
  `auth.methods.password:`. Do not "fix" this; the newer layout belongs to v2.1.x and would fail validation here.
- `server.searchResultsLimit`, `server.database.quotas`, `shareDefaults`,
  `userDefaults.account.showAdvancedProfile`, `userDefaults.listing.promptRightCloseButton`,
  `userDefaults.listing.newFileTemplate`, `userDefaults.listing.showTypeColumn`,
  `userDefaults.listing.showCreationDateColumn` do **not** exist in v2.0.1. Do not add them.
- `userDefaults.fileViewer.editorQuickSave` **does** exist in v2.0.1. Keep it.
- Tooling confirmed present: PyYAML 6.0.3, shellcheck 0.11.0, docker with a reachable daemon.

---

### Task 1: Capture baselines, upstream reference, and the config checker (RED)

**Files:**

- Create: `/tmp/baseline/` (copies of the three target files)
- Create: `/tmp/config-generated-v2.0.1.yaml`
- Create: `/tmp/check-config.py`

- [ ] **Step 1: Snapshot the current files so the diff at the end is meaningful**

Run:

```bash
mkdir -p /tmp/baseline
cd /data/arch-filebrowser-quantum
cp Dockerfile /tmp/baseline/Dockerfile
cp run/nobody/start.sh /tmp/baseline/start.sh
cp config/config.yaml /tmp/baseline/config.yaml
ls -l /tmp/baseline
```

Expected: three files listed.

- [ ] **Step 2: Fetch the pinned upstream reference**

Run:

```bash
curl -sS --max-time 30 \
  https://raw.githubusercontent.com/gtsteffaniak/filebrowser/v2.0.1-stable/frontend/public/config.generated.yaml \
  -o /tmp/config-generated-v2.0.1.yaml
wc -l /tmp/config-generated-v2.0.1.yaml
grep -c "adminUsername" /tmp/config-generated-v2.0.1.yaml
```

Expected: a non-zero line count, and the `grep` finds `adminUsername` (proving the v2.0.1 layout, where it sits at
`auth:` level).

- [ ] **Step 3: Write the checker**

Create `/tmp/check-config.py` with exactly this content:

```python
#!/usr/bin/env python3
"""Validate config/config.yaml against the pinned upstream v2.0.1 reference."""

import re
import sys

import yaml

REFERENCE = "/tmp/config-generated-v2.0.1.yaml"
CONFIG = "config/config.yaml"

# The only key paths allowed to be uncommented. List indexes are stripped
# before comparison so server.sources[0] matches server.sources.
EXPECTED_ACTIVE = {
    "auth.methods.password.enabled",
    "auth.methods.password.minLength",
    "http.port",
    "server.cacheDir",
    "server.database.path",
    "server.sources.config.defaultEnabled",
    "server.sources.name",
    "server.sources.path",
}

# A key-like line: optional comment marker, optional list dash, then name:.
KEY_LINE = re.compile(r"^\s*(?:#\s*)?(?:-\s+)?([A-Za-z0-9_-]+):(?:\s|$)")

SECRET_KEYS = (
    "adminPassword",
    "totpSecret",
    "clientSecret",
    "userPassword",
    "key",
    "secret",
)


def leaf_paths(node, prefix=""):
    """Yield dotted paths for every scalar leaf (list indexes removed)."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield from leaf_paths(value, f"{prefix}.{key}" if prefix else str(key))
    elif isinstance(node, list):
        for value in node:
            yield from leaf_paths(value, prefix)
    elif node is not None:
        yield prefix


def key_names(node):
    """Yield every mapping key name at every depth."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield str(key)
            yield from key_names(value)
    elif isinstance(node, list):
        for value in node:
            yield from key_names(value)


def main():
    failures = []

    with open(CONFIG, encoding="utf-8") as handle:
        text = handle.read()

    try:
        parsed = yaml.safe_load(text)
    except yaml.YAMLError as error:
        print(f"FAIL yaml parse: {error}")
        return 1

    # 1. active surface
    active = set(leaf_paths(parsed))
    missing_active = EXPECTED_ACTIVE - active
    extra_active = active - EXPECTED_ACTIVE
    if missing_active:
        failures.append(f"active keys missing: {sorted(missing_active)}")
    if extra_active:
        failures.append(f"unexpected active keys: {sorted(extra_active)}")

    # 2. full coverage of the upstream surface, plus typo detection
    with open(REFERENCE, encoding="utf-8") as handle:
        reference = yaml.safe_load(handle)
    reference_names = set(key_names(reference))
    file_names = {
        match.group(1)
        for match in (KEY_LINE.match(line) for line in text.splitlines())
        if match
    }
    missing_keys = reference_names - file_names
    unknown_keys = file_names - reference_names
    if missing_keys:
        failures.append(f"missing upstream keys: {sorted(missing_keys)}")
    if unknown_keys:
        failures.append(f"keys not in upstream reference: {sorted(unknown_keys)}")

    # 3. no secret is active
    for line_number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        for secret in SECRET_KEYS:
            if re.match(rf"^{secret}:", stripped):
                failures.append(f"active secret at line {line_number}: {stripped}")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        return 1

    print(f"PASS yaml parses; {len(active)} active keys; "
          f"{len(reference_names)} upstream keys covered; no active secrets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the checker against the current draft and confirm it fails**

Run:

```bash
cd /data/arch-filebrowser-quantum
python3 /tmp/check-config.py; echo "exit=$?"
```

Expected: `exit=1` with `FAIL` lines — the draft is missing dozens of upstream keys and has an unexpected active key
shape (`auth.adminUsername` is not in the expected active set). This is the RED step that proves the checker detects
gaps.

- [ ] **Step 5: Commit nothing yet**

No repo change has been made in this task, so there is nothing to commit.

---

### Task 2: Author the reference configuration

**Files:**

- Modify: `config/config.yaml` (full replacement)

- [ ] **Step 1: Replace `config/config.yaml` with this content**

```yaml
# =============================================================================
# FileBrowser Quantum - reference configuration for this container image
# =============================================================================
#
# ONLY the basic settings are active. Everything else is commented out -
# uncomment what you need and restart the container.
#
# Setting names are validated at startup: an unknown or misspelled key stops
# the server, so keep names exactly as written here.
#
# Pinned to upstream v2.0.1-stable, the release pulled by build/root/install.sh
# when this image is built.
#
#   reference  https://github.com/gtsteffaniak/filebrowser/blob/v2.0.1-stable/frontend/public/config.generated.yaml
#   docs       https://filebrowserquantum.com/en/docs/configuration/
#
# Secrets appear commented, each with the FILEBROWSER_* environment variable
# this image already exports. Prefer the environment variable: a secret
# written here is stored in plain text on disk and, for adminPassword, is
# re-applied on every container start.
#
# After upgrading to a new upstream release, re-check this file against the
# generated reference above - option names and locations do change between
# minor versions.
# =============================================================================

# -----------------------------------------------------------------------------
# Server - sources, caching, database, indexing, previews, logging
# docs  /docs/configuration/server/  and  /docs/configuration/logging/
# -----------------------------------------------------------------------------
server:
  # minimum length of a search query before searching starts
  # minSearchLength: 3

  # disable the backend update check service
  # disableUpdateCheck: false

  # concurrent image processing jobs used to build previews
  # numImageProcessors: 4

  # disable all previews and thumbnails, simple icons are used instead
  # disablePreviews: false

  # disable preview resizing, faster over slow connections
  # disablePreviewResize: false

  # disable type detection by file header, useful on slow filesystems
  # disableTypeDetectionByHeader: false

  # logging - a list, one entry per output destination
  # docs  /docs/configuration/logging/
  # logging:
  #   - levels: "info|warning|error"       # levels to log, or "disabled"
  #     apiLevels: ""                      # levels for API routes, or "disabled"
  #     output: "stdout"                   # "stdout" or a file path
  #     noColors: false                    # disable coloured output, use for files
  #     json: false                        # emit JSON formatted lines
  #     utc: false                         # log in UTC instead of local time
  #     apiFilter: ""                      # regex of API paths to omit from logs

  # file system sources - at least one is required
  # docs  /docs/configuration/sources/
  sources:
    - path: "/media"                  # the files bind mount
      name: "Media"                   # display name in the UI
      config:
        defaultEnabled: true          # grant this source to all users

        # per-source options for the source above - uncomment as needed
        # denyByDefault: false              # deny access unless an allow rule exists
        # private: false                    # no sharing permitted for this source
        # readOnly: false                   # disable changes from UI, WebDAV and API
        # disabled: false                   # keep the source defined but switched off
        # defaultUserScope: "/"             # default access path inside the source
        # createUserDir: false              # create defaultUserScope/<username> per user
        # useLogicalSize: false             # size from file contents, not disk usage
        # defaultPermissions:               # template permissions for new user scopes
        #   view: false
        #   download: false
        #   modify: false
        #   delete: false
        #   create: false
        #   configured: false               # true when explicitly set, allows deny-all
        # rules:                            # per-path indexing and visibility rules
        #   - neverWatchPath: ""            # index once in the first pass, never re-index
        #     includeRootItem: ""           # only include these items at root level
        #     fileStartsWith: ""            # exclude files by prefix
        #     folderStartsWith: ""          # exclude folders by prefix
        #     fileEndsWith: ""              # exclude files by suffix
        #     folderEndsWith: ""            # exclude folders by suffix
        #     folderPath: ""                # exclude this folder path
        #     filePath: ""                  # exclude this file path
        #     fileName: ""                  # exclude files by name
        #     folderName: ""                # exclude folders by name
        #     viewable: false               # visible in the UI but not indexed
        #     ignoreHidden: false           # exclude hidden files and folders
        #     ignoreZeroSizeFolders: false  # exclude folders with 0 size
        #     ignoreSymlinks: false         # exclude symbolic links

  # additional sources use the same block again, for example
  # sources:
  #   - path: "/media/downloads"
  #     name: "Downloads"
  #     config:
  #       defaultEnabled: false

  # cache for previews, the search index (cacheDir/sql) and archive temporary files
  cacheDir: "/config/filebrowser/cache"

  # automatically clean the cache directory - docker must mount a persistent
  # volume for the cache to survive container recreation
  # cacheDirCleanup: false

  # maximum archive/unarchive size in GB, 0 means no limit
  # maxArchiveSize: 20

  # permissions applied to files and directories created through the UI
  # filesystem:
  #   createFilePermission: "644"       # 644, 755, 2755
  #   createDirectoryPermission: "755"  # 755, 2755, 1777

  # index database tuning - raise batchSize and cacheSizeMB for very large trees
  # indexSqlConfig:
  #   batchSize: 1000                   # items per transaction, typically 500-5000
  #   cacheSizeMB: 32                   # SQLite cache size in MB
  #   walMode: false                    # WAL journaling, better for busy deployments
  #   disableReuse: false               # true always creates a new index on startup
  #   startupIntegrityCheck: "quickCheck"  # quickCheck | probe | off

  # sqlite database holding users, shares and activity
  database:
    path: "/config/filebrowser/database.sqlite"
    # migrateFrom: ""                 # one-time v1 to v2 migration source file
    # activity:                       # semantic activity audit logging
    #   disabled: false
    #   retentionDays: 30             # purge activity rows older than this
    #   flushIntervalSeconds: 10      # buffered write interval
    #   maxBufferSize: 10000          # flush early once the buffer reaches this size
  # NOTE - the active path above takes precedence over FILEBROWSER_DATABASE_PATH.
  # Remove the path key if you set that environment variable instead.

# -----------------------------------------------------------------------------
# Authentication - password, proxy, OIDC, LDAP, JWT and passkey
# docs  /docs/configuration/authentication/
# -----------------------------------------------------------------------------
auth:
  # hours a web UI session token stays valid
  # tokenExpirationHours: 2

  methods:
    # password login
    password:
      enabled: true
      minLength: 8                    # minimum password length
      # signup: false                 # allow self signup from the login page
      # enforcedOtp: false            # force TOTP for all password users
      # recaptcha:                    # login page captcha, used with signup
      #   host: "https://www.google.com/recaptcha/api.js"
      #   key: ""                     # recaptcha v2 site key
      #   secret: ""                  # prefer FILEBROWSER_RECAPTCHA_SECRET

    # reverse proxy header authentication - the header value is trusted as the
    # username, only enable behind a proxy you control
    # proxy:
    #   enabled: false
    #   header: ""                    # header carrying the username
    #   adminGroup: ""                # users in this group become admins
    #   userGroups: ""                # if set, only these groups may log in
    #   groupsClaim: ""               # JSON field to read groups from
    #   userIdentifier: ""            # field used as the username
    #   disableVerifyTLS: false       # insecure, testing only
    #   logoutRedirectUrl: ""         # provider logout url to redirect to

    # disable all authentication - overrides every other method, unsafe
    # noauth: false

    # OpenID Connect
    # oidc:
    #   enabled: false
    #   clientId: ""                  # prefer FILEBROWSER_OIDC_CLIENT_ID
    #   clientSecret: ""              # prefer FILEBROWSER_OIDC_CLIENT_SECRET
    #   issuerUrl: ""                 # authorization url of the provider
    #   scopes: "openid email profile"
    #   userIdentifier: "preferred_username"
    #   adminGroup: ""                # users in this group become admins
    #   userGroups: ""                # if set, only these groups may log in
    #   groupsClaim: "groups"
    #   disableVerifyTLS: false       # insecure, testing only
    #   logoutRedirectUrl: ""

    # LDAP
    # ldap:
    #   enabled: false
    #   server: ""                    # ldap://host:389
    #   baseDN: ""                    # e.g. dc=example,dc=com
    #   userDN: ""                    # bind DN of the service account
    #   userPassword: ""              # prefer FILEBROWSER_LDAP_USER_PASSWORD
    #   userFilter: ""                # defaults to (&(cn=%s)(objectClass=user))
    #   adminGroup: ""                # users in this group become admins
    #   userGroups: ""                # if set, only these groups may log in
    #   groupsClaim: ""               # JSON field to read groups from
    #   userIdentifier: ""            # field used as the username
    #   disableVerifyTLS: false       # insecure, testing only
    #   logoutRedirectUrl: ""

    # JWT bearer authentication
    # jwt:
    #   enabled: false
    #   header: "X-JWT-Assertion"     # header carrying the token
    #   secret: ""                    # public key, certificate or shared secret
    #   algorithm: "HS256"            # HS256, HS384, HS512, RS256, ES256
    #   adminGroup: ""                # users in this group become admins
    #   userGroups: ""                # if set, only these groups may log in
    #   groupsClaim: ""               # JSON field to read groups from
    #   userIdentifier: ""            # field used as the username
    #   disableVerifyTLS: false       # insecure, testing only
    #   logoutRedirectUrl: ""

    # passkey multi-factor authentication
    # passkey:
    #   enabled: false
    #   rpDisplayName: ""             # defaults to the frontend name
    #   rpId: ""                      # defaults to the base URL host
    #   rpOrigins: ""                 # defaults to the base URL
    #   loginButtonText: ""           # custom login button label

  # admin account created on first start
  # adminUsername: "admin"            # no environment variable equivalent
  # adminPassword: "admin"            # prefer FILEBROWSER_ADMIN_PASSWORD -
  #                                   #   a value here is re-applied on every start

  # HMAC key for JWT tokens - generated into the database when unset
  # key: ""

  # secret used to encrypt TOTP secrets
  # totpSecret: ""                    # prefer FILEBROWSER_TOTP_SECRET

# -----------------------------------------------------------------------------
# Frontend - branding, default links, navigation, styling
# docs  /docs/configuration/frontend/
# -----------------------------------------------------------------------------
frontend:
  # display name, also used as the PWA install name (capped at 30 characters)
  # name: "FileBrowser Quantum"

  # disable the default links in the sidebar
  # disableDefaultLinks: false

  # disable the used-percentage indicator for sources in the sidebar
  # disableUsedPercentage: false

  # disable the sidebar navigation buttons
  # disableNavButtons: false

  # path to a favicon
  # favicon: ""

  # html head meta description
  # description: "FileBrowser Quantum is a file manager for the web"

  # path to an image used as the login page icon
  # loginIcon: ""

  # login button labels
  # loginButtonText: ""
  # oidcLoginButtonText: ""

  # hide the PWA install button in the sidebar
  # disablePWAInstall: false

  # extra links shown in the sidebar
  # externalLinks:
  #   - text: "Project home"          # link text
  #     title: "Project home page"    # tooltip
  #     url: "https://example.com/"
  #   - text: "Help"
  #     title: "Documentation"
  #     url: "https://filebrowserquantum.com/en/docs/"

  # styling and custom themes
  # styling:
  #   disableEventThemes: false       # disable the event based themes
  #   customCSS: ""                   # css file applied for all users
  #   lightBackground: "#f5f5f5"      # any valid CSS colour
  #   darkBackground: "#141D24"       # any valid CSS colour
  #   customThemes:                   # selectable per user, "default" is the default
  #     alternative:
  #       description: "Reduce rounded corners"
  #       css: "reduce-rounded-corners.css"
  #     default:
  #       description: "The default theme"
  #       css: ""

# -----------------------------------------------------------------------------
# User defaults - initial values seeded for new users on first start
# docs  /docs/configuration/users/  (values become database-authoritative
# after first start; remove this block once the defaults are set in the UI)
# -----------------------------------------------------------------------------
# userDefaults:
#   sidebar:
#     disableQuickToggles: false      # hide the quick toggles
#     hideFileActions: false          # hide file actions
#     disableHideOnPreview: false     # keep the sidebar open while previewing
#     sticky: true                    # keep the sidebar open when navigating
#     hideFiles: false                # show directories only in the tree
#     showTools: true                 # show sidebar links of category "tool"
#   listing:
#     deleteWithoutConfirming: false  # delete without a confirmation prompt
#     dateFormat: false               # true shows exact timestamps, false relative
#     showHidden: false               # show hidden files
#     quickDownload: false            # one-click download icon
#     showSelectMultiple: false       # multi-select on desktop
#     singleClick: false              # open folders on single click
#     hideFileExt: ""                 # space separated extensions to hide
#     showCopyPath: false             # copy path in the context menu
#     deleteAfterArchive: true        # delete sources after archiving
#     viewMode: "normal"              # normal, list, grid or compact
#     gallerySize: 3                  # 0-9 gallery thumbnail size
#   preview:
#     image: true                     # thumbnails for images
#     video: true                     # thumbnails for videos
#     audio: true                     # thumbnails for audio
#     motionVideoPreview: true        # several frames when hovering a video
#     office: true                    # thumbnails for office documents
#     popup: true                     # larger popup preview on hover
#     disablePreviewExt: ""           # comma separated extensions to skip
#     highQuality: true               # high quality thumbnails
#     folder: true                    # folder previews
#     models: true                    # live 3D model thumbnails
#   fileViewer:
#     editorQuickSave: false          # quick save button in the editor
#     autoplayMedia: true             # autoplay media in the preview
#     disableViewingExt: ""           # comma separated extensions not viewable
#     disableOnlyOfficeExt: ".md .txt .pdf .html .xml"
#     preferEditorForMarkdown: false  # editor instead of the markdown viewer
#     debugOffice: false              # debug the onlyoffice integration
#   search:
#     disableOptions: false           # hide the search options
#   ui:
#     darkMode: true                  # start in dark mode
#     themeColor: "var(--blue)"       # e.g. #ff0000 or var(--red)
#     customTheme: ""                 # name of a theme from frontend styling
#     locale: "en"                    # de, en, fr, ...
#   fileLoading:
#     maxConcurrentUpload: 10         # parallel uploads
#     uploadChunkSizeMb: 10           # upload chunk size in MB
#     clearAll: false                 # clear the queue after completion
#     downloadChunkSizeMb: 0          # 0 disables chunked downloads
#   account:
#     permissions:
#       api: false                    # allow API access
#       admin: false                  # allow admin access
#       share: false                  # allow sharing files
#       realtime: false               # allow realtime updates
#     lockPassword: false             # prevent password changes
#     requirePasswordChange: false    # force a password change at next login
#     disableSettings: false          # hide the settings page
#     loginMethod: "password"         # password, proxy or oidc
#     disableUpdateNotifications: false  # hide the update banner for admins

# -----------------------------------------------------------------------------
# Integrations - OnlyOffice document server and media processing
# docs  /docs/configuration/  (integrations section)
# -----------------------------------------------------------------------------
integrations:
  # OnlyOffice document server, needs to be reachable from the browser
  # office:
  #   url: "http://onlyoffice-server:8000"
  #   internalUrl: ""                 # private address for server-to-server calls
  #   secret: ""                      # prefer FILEBROWSER_ONLYOFFICE_SECRET
  #   viewOnly: false                 # disable editing

  # media processing, requires ffmpeg and ffprobe
  # media:
  #   ffmpegPath: "/usr/local/bin"    # directory containing ffmpeg and ffprobe
  #   debug: false                    # verbose ffmpeg output, very noisy
  #   extractEmbeddedSubtitles: false # extract subtitles from media files
  #   hardwareAcceleration: false     # use hardware ffmpeg when available
  #   convert:                        # which formats are converted for previews
  #     imagePreview:
  #       heic: false
  #       jpeg: true
  #     videoPreview:
  #       3g2: true
  #       3gp: true
  #       asf: true
  #       avi: true
  #       f4v: true
  #       flv: true
  #       m2ts: true
  #       m4v: true
  #       mkv: true
  #       mov: true
  #       mp4: true
  #       mpeg: true
  #       mpg: true
  #       ogv: true
  #       ts: true
  #       vob: true
  #       webm: true
  #       wmv: true

# -----------------------------------------------------------------------------
# HTTP - listening socket, TLS, base URL and reverse proxy behaviour
# docs  /docs/configuration/http/
# -----------------------------------------------------------------------------
http:
  port: 8125                        # webui port published by this template
  # listen: ""                      # bind address, default 0.0.0.0
  # baseURL: "/"                    # subpath when served behind a proxy prefix
  # externalUrl: ""                 # public url used for share links
  # internalUrl: ""                 # private url used by integrations
  # socket: ""                      # unix socket instead of a TCP port
  # tlsCert: ""                     # path to the certificate, set with tlsKey
  # tlsKey: ""                      # path to the private key
  # disableWebDAV: false            # remove the /dav route
  # trustProxyHeaders: false        # honour X-Forwarded-* and X-Real-IP
  # disableRateLimit: false         # disable auth throttling and lockout
```

- [ ] **Step 2: Run the checker and expect PASS**

Run:

```bash
cd /data/arch-filebrowser-quantum
python3 /tmp/check-config.py; echo "exit=$?"
```

Expected: `PASS yaml parses; 8 active keys; <N> upstream keys covered; no active secrets` and `exit=0`.

If it reports `missing upstream keys`, add the named key as a commented line in the correct section and re-run. If it
reports `keys not in upstream reference`, you invented a key name — correct the spelling. If it reports
`unexpected active keys`, a line lost its `#` - re-comment it.

- [ ] **Step 3: Commit**

```bash
cd /data/arch-filebrowser-quantum
git add config/config.yaml
git commit -m "feat: add complete FileBrowser Quantum reference config"
```

---

### Task 3: Bundle the seed in the image

**Files:**

- Modify: `Dockerfile:20-23` (the `ADD run/nobody/*.sh` block)

- [ ] **Step 1: Add the seed to the additional-files block**

The current block is:

```dockerfile
# add supervisor conf file for app
ADD build/*.conf /etc/supervisor/conf.d/

# add install bash script
ADD build/root/*.sh /root/

# add start bash script
ADD run/nobody/*.sh /home/nobody/
```

Change it to:

```dockerfile
# add supervisor conf file for app
ADD build/*.conf /etc/supervisor/conf.d/

# add install bash script
ADD build/root/*.sh /root/

# add start bash script
ADD run/nobody/*.sh /home/nobody/

# add default configuration seed, copied to /config on first run by start.sh
ADD config/config.yaml /opt/filebrowser/config.default.yaml
```

- [ ] **Step 2: Verify the edit landed exactly once**

Run:

```bash
cd /data/arch-filebrowser-quantum
grep -n "config.default.yaml" Dockerfile
diff -u /tmp/baseline/Dockerfile Dockerfile | head -20
```

Expected: exactly one `grep` hit, and the diff shows only the added comment plus `ADD` lines.

- [ ] **Step 3: Commit**

```bash
cd /data/arch-filebrowser-quantum
git add Dockerfile
git commit -m "feat: bundle default config seed in the image"
```

---

### Task 4: Seed and migrate the config in start.sh

**Files:**

- Modify: `run/nobody/start.sh` (full replacement)

- [ ] **Step 1: Replace `run/nobody/start.sh` with this content**

```bash
#!/usr/bin/dumb-init /bin/bash
# shellcheck shell=bash

# no config bind mount
if [[ ! -d "/config" ]]; then
	echo "[crit] /config bind mount not found, exiting..." ; exit 1
fi

# define config and data paths
config_file="/config/config.yaml"
seed_config_file="/opt/filebrowser/config.default.yaml"
legacy_config_file="/config/filebrowser/config/config.yaml"
data_root="/config/filebrowser"
filebrowser_install_path="/opt/filebrowser"

# create data path, used for the cache and the database
mkdir -p "${data_root}"

# seed or migrate the config on first run, an existing config is never overwritten
if [[ ! -f "${config_file}" ]]; then
	if [[ -f "${legacy_config_file}" ]]; then
		echo "[info] Migrating existing config from '${legacy_config_file}' to '${config_file}'..."
		if ! cp "${legacy_config_file}" "${config_file}"; then
			echo "[crit] Failed to migrate config to '${config_file}', exiting..." ; exit 1
		fi
		echo "[info] Migration complete, '${legacy_config_file}' is no longer used and can be removed."
	elif [[ -f "${seed_config_file}" ]]; then
		echo "[info] Seeding default config to '${config_file}'..."
		if ! cp "${seed_config_file}" "${config_file}"; then
			echo "[crit] Failed to seed config to '${config_file}', exiting..." ; exit 1
		fi
	else
		echo "[crit] No config at '${config_file}' and no seed at '${seed_config_file}', exiting..." ; exit 1
	fi
elif [[ -f "${legacy_config_file}" ]]; then
	echo "[info] Using '${config_file}', ignoring obsolete '${legacy_config_file}'."
fi

# export env vars
export FILEBROWSER_ADMIN_PASSWORD="${FILEBROWSER_ADMIN_PASSWORD}"
export FILEBROWSER_JWT_TOKEN_SECRET="${FILEBROWSER_JWT_TOKEN_SECRET}"
export FILEBROWSER_TOTP_SECRET="${FILEBROWSER_TOTP_SECRET}"
export FILEBROWSER_RECAPTCHA_SECRET="${FILEBROWSER_RECAPTCHA_SECRET}"
export FILEBROWSER_LDAP_USER_PASSWORD="${FILEBROWSER_LDAP_USER_PASSWORD}"
export FILEBROWSER_OIDC_CLIENT_ID="${FILEBROWSER_OIDC_CLIENT_ID}"
export FILEBROWSER_OIDC_CLIENT_SECRET="${FILEBROWSER_OIDC_CLIENT_SECRET}"
export FILEBROWSER_ONLYOFFICE_SECRET="${FILEBROWSER_ONLYOFFICE_SECRET}"
export FILEBROWSER_CONFIG="${FILEBROWSER_CONFIG}"
export FILEBROWSER_DATABASE_PATH="${FILEBROWSER_DATABASE_PATH}"
export FILEBROWSER_FFMPEG_PATH="${FILEBROWSER_FFMPEG_PATH}"
export FILEBROWSER_DISABLE_AUTOMATIC_BACKUP="${FILEBROWSER_DISABLE_AUTOMATIC_BACKUP}"

# export any additional parameters
export ADDITIONAL_PARAMETERS="${ADDITIONAL_PARAMETERS}"

# run filebrowser with appropriate options
# ${ADDITIONAL_PARAMETERS} is intentionally unquoted so several flags can be passed
# shellcheck disable=SC2086
"${filebrowser_install_path}/filebrowser" \
	--config "${config_file}" \
	${ADDITIONAL_PARAMETERS}
```

- [ ] **Step 2: Syntax-check and lint**

Run:

```bash
cd /data/arch-filebrowser-quantum
bash -n run/nobody/start.sh && echo "syntax OK"
shellcheck run/nobody/start.sh; echo "shellcheck exit=$?"
```

Expected: `syntax OK` and `shellcheck exit=0` with no findings.

- [ ] **Step 3: Confirm only the intended regions changed**

Run:

```bash
cd /data/arch-filebrowser-quantum
diff -u /tmp/baseline/start.sh run/nobody/start.sh
```

Expected: differences limited to the path block, the new seeding block, the two ShellCheck directives
(`# shellcheck shell=bash` and `# shellcheck disable=SC2086`), and `--config "${config_file}"`. Every
`export FILEBROWSER_*` line and the `ADDITIONAL_PARAMETERS` export must be byte-identical to the baseline.

- [ ] **Step 4: Commit**

```bash
cd /data/arch-filebrowser-quantum
git add run/nobody/start.sh
git commit -m "feat: seed or migrate config on first container start"
```

---

### Task 5: Prove the seeding behaviour matrix

**Files:**

- Create: `/tmp/simulate-seeding.sh`

Docker builds need network access, so the primary behavioural test remaps `start.sh`'s absolute paths into a temp tree
and stubs the binary. It exercises the real script, not a copy of its logic.

- [ ] **Step 1: Write the simulator**

Create `/tmp/simulate-seeding.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Exercise run/nobody/start.sh's seeding branches without a container build.
set -uo pipefail

REPO="/data/arch-filebrowser-quantum"
WORK="/tmp/seed-sim"
failures=0

fail() {
	echo "FAIL $1"
	failures=$(( failures + 1 ))
}

reset() {
	rm -rf "${WORK}"
	mkdir -p "${WORK}/opt" "${WORK}/config" "${WORK}/bin"
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %s/bin/calls.log\n' "${WORK}" > "${WORK}/opt/filebrowser"
	chmod +x "${WORK}/opt/filebrowser"
	cp "${REPO}/config/config.yaml" "${WORK}/opt/config.default.yaml"
	sed -e "s#/opt/filebrowser#${WORK}/opt#g" \
		-e "s#\"/config\"#\"${WORK}/config\"#" \
		-e "s#\"/config/#\"${WORK}/config/#" \
		"${REPO}/run/nobody/start.sh" > "${WORK}/start.sh"
	chmod +x "${WORK}/start.sh"
}

# 1. fresh start seeds the config and passes --config on the command line
reset
"${WORK}/start.sh" > "${WORK}/out.log" 2>&1
[[ -f "${WORK}/config/config.yaml" ]] || fail "1: config not seeded"
cmp -s "${WORK}/opt/config.default.yaml" "${WORK}/config/config.yaml" || fail "1: seeded file differs from seed"
grep -q -- "--config ${WORK}/config/config.yaml" "${WORK}/bin/calls.log" || fail "1: --config argument wrong"

# 2. an existing config is never overwritten
reset
printf '# user edited\nhttp:\n  port: 9999\n' > "${WORK}/config/config.yaml"
"${WORK}/start.sh" > "${WORK}/out.log" 2>&1
grep -q "port: 9999" "${WORK}/config/config.yaml" || fail "2: existing config was overwritten"

# 3. a legacy config is migrated and left in place
reset
mkdir -p "${WORK}/config/filebrowser/config"
printf '# legacy\nhttp:\n  port: 8125\n' > "${WORK}/config/filebrowser/config/config.yaml"
"${WORK}/start.sh" > "${WORK}/out.log" 2>&1
cmp -s "${WORK}/config/filebrowser/config/config.yaml" "${WORK}/config/config.yaml" \
	|| fail "3: legacy config not migrated"
[[ -f "${WORK}/config/filebrowser/config/config.yaml" ]] || fail "3: legacy config was removed"
grep -q "Migrating existing config" "${WORK}/out.log" || fail "3: migration not logged"

# 4. legacy plus new config uses the new one and says so
reset
mkdir -p "${WORK}/config/filebrowser/config"
printf '# legacy\n' > "${WORK}/config/filebrowser/config/config.yaml"
printf '# new\nhttp:\n  port: 8125\n' > "${WORK}/config/config.yaml"
"${WORK}/start.sh" > "${WORK}/out.log" 2>&1
grep -q "ignoring obsolete" "${WORK}/out.log" || fail "4: obsolete legacy config not reported"

# 5. no config and no seed exits non-zero with a crit message
reset
rm -f "${WORK}/opt/config.default.yaml"
if "${WORK}/start.sh" > "${WORK}/out.log" 2>&1; then
	fail "5: expected a non-zero exit"
fi
grep -q "\[crit\]" "${WORK}/out.log" || fail "5: no crit message"

if (( failures > 0 )); then
	echo "${failures} check(s) failed"
	exit 1
fi
echo "PASS 5 seeding scenarios"
```

- [ ] **Step 2: Run the simulator**

Run:

```bash
bash /tmp/simulate-seeding.sh; echo "exit=$?"
```

Expected: `PASS 5 seeding scenarios` and `exit=0`.

If scenario 1 fails with "config not seeded", the `sed` remap in `reset` did not match the script's paths - check
that `start.sh` still uses the literal `/config`, `/config/` and `/opt/filebrowser` strings inside double quotes. Both
`/config` expressions are anchored on the opening quote and are **not** global: `legacy_config_file` contains two
`/config/` segments, and a global replace would rewrite both, producing a mangled duplicate path.

- [ ] **Step 3: Commit nothing**

The simulator lives in `/tmp` and is intentionally not committed.

---

### Task 6: Container smoke test

**Files:** none (build only)

Skipping this task is acceptable **only** if the build fails for network reasons; record that fact rather than
reporting success.

- [ ] **Step 1: Build the image**

Run:

```bash
cd /data/arch-filebrowser-quantum
docker build -f Dockerfile -t filebrowser-quantum:config-test . 2>&1 | tail -20
```

Expected: build completes and the final line names the tag. If the build cannot reach the network, note it and skip to
Task 7, reporting the container checks as **not run**.

- [ ] **Step 2: Start with an empty /config and confirm seeding**

Run:

```bash
rm -rf /tmp/fb-config-test && mkdir -p /tmp/fb-config-test
docker run -d --name fb-config-test \
  -v /tmp/fb-config-test:/config \
  filebrowser-quantum:config-test
sleep 8
ls -l /tmp/fb-config-test/config.yaml
docker logs fb-config-test 2>&1 | grep -E "Seeding|Migrating|crit" | head -5
```

Expected: `/tmp/fb-config-test/config.yaml` exists and the log shows the seeding message.

- [ ] **Step 3: Confirm an edited config survives a restart**

Run:

```bash
printf '# edited by operator\n' >> /tmp/fb-config-test/config.yaml
docker restart fb-config-test && sleep 8
tail -1 /tmp/fb-config-test/config.yaml
docker rm -f fb-config-test
```

Expected: the last line is `# edited by operator` - the seed did not overwrite it.

---

### Task 7: Final verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Run every static gate**

Run:

```bash
cd /data/arch-filebrowser-quantum
python3 /tmp/check-config.py; echo "config exit=$?"
bash -n run/nobody/start.sh; echo "syntax exit=$?"
shellcheck run/nobody/start.sh; echo "shellcheck exit=$?"
bash /tmp/simulate-seeding.sh; echo "simulation exit=$?"
markdownlint docs/agent/specs/2026-10-18-default-config-yaml-design.md >/dev/null 2>&1; echo "spec lint exit=$?"
```

Expected: `config exit=0`, `syntax exit=0`, `shellcheck exit=0`, `simulation exit=0`. `spec lint` may report
default-80-column MD013 warnings on table rows; that is within the project's 120-character limit and is not a failure.

- [ ] **Step 2: Confirm the working tree contains only the intended changes**

Run:

```bash
cd /data/arch-filebrowser-quantum
git status --short
git log --oneline -5
```

Expected: the three target files are committed, no `/tmp` artefacts appear in the repo, and no unrelated file was
modified. Files that were already untracked before this work (`.github/`, `LICENSE`, `README.md`, `build/`) may still
appear as untracked - leave them alone.

- [ ] **Step 3: Confirm README and install.sh are untouched**

Run:

```bash
cd /data/arch-filebrowser-quantum
git status --short README.md build/root/install.sh
```

Expected: no output - both are out of scope per the spec.
