# Application

[FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser)

## Description

FileBrowser Quantum provides a file managing interface within a specified
directory. It can be used to upload, delete, preview and edit files from a web
browser.

## Build notes

The image installs the latest GitHub release. The seeded configuration is
written against v2.0.1-stable, the release the image installs today. Options are
added and removed between upstream releases, and uncommenting a key the installed
release no longer knows about stops the server, so compare the version the image
ships (`filebrowser version`) with the reference tag before uncommenting a key
you are unsure about.

## Usage

```bash
docker run -d \
        --name=<container name> \
        -p <webui port>:8125 \
        -v <path for config files>:/config \
        -v <path for files>:/media \
        -v /etc/localtime:/etc/localtime:ro \
        -e FILEBROWSER_ADMIN_PASSWORD=<admin password> \
        -e FILEBROWSER_JWT_TOKEN_SECRET=<jwt token secret> \
        -e FILEBROWSER_TOTP_SECRET=<totp secret> \
        -e FILEBROWSER_RECAPTCHA_SECRET=<recaptcha secret> \
        -e FILEBROWSER_LDAP_USER_PASSWORD=<ldap bind password> \
        -e FILEBROWSER_OIDC_CLIENT_ID=<oidc client id> \
        -e FILEBROWSER_OIDC_CLIENT_SECRET=<oidc client secret> \
        -e FILEBROWSER_ONLYOFFICE_SECRET=<onlyoffice secret> \
        -e FILEBROWSER_DISABLE_AUTOMATIC_BACKUP=<true|false> \
        -e FILEBROWSER_CONFIG=/config/filebrowser/config/config.yaml \
        -e FILEBROWSER_DATABASE_PATH=/config/filebrowser/db/filebrowser.sqlite \
        -e FILEBROWSER_FFMPEG_PATH=/usr/local/bin \
        -e ADDITIONAL_PARAMETERS=<cli options> \
        -e ENABLE_HEALTHCHECK=<yes|no> \
        -e HEALTHCHECK_COMMAND=<command> \
        -e HEALTHCHECK_ACTION=<action> \
        -e HEALTHCHECK_HOSTNAME=<hostname> \
        -e PUID=<uid for user> \
        -e PGID=<gid for user> \
        -e UMASK=<umask for created files> \
        ghcr.io/binhex/arch-filebrowser-quantum
```

Please replace all user variables in the above command defined by <> with the
correct values.

## Access application

`http://<host ip>:8125`

The default username is `admin`. The seeded config sets no admin password, so
FileBrowser generates a random password on first start, writes it to
`/config/filebrowser/logs/filebrowser.log`, and forces a password change at
first login.

Set `FILEBROWSER_ADMIN_PASSWORD` to choose your own password instead. It is
re-applied on every start, so remove the variable once you have changed the
password in the UI. A value shorter than the configured minimum password
length (8 in the seeded config) is rejected once the admin account exists (the
previous password is kept), while a fresh install accepts the first value. The
literal value `admin` is treated as unset, so setting it does not give you
`admin/admin`.

## Configuration

On first start the container seeds a commented reference configuration to
`FILEBROWSER_CONFIG` (default `/config/filebrowser/config/config.yaml`). Only
the basics are active: the webui port, the `/media` source, the cache directory,
logging and password authentication. Every other option is present but commented
out - uncomment the ones you need and restart the container.

- The file is seeded whenever the configured path is absent or empty. An
  existing config is never overwritten, so your edits survive a restart.
- At startup the container removes leftover temporary files next to the config
  (`<config file>.tmp.*`) older than five minutes - do not store anything under
  that name.
- The seeded config writes logs to
  `/config/filebrowser/logs/filebrowser.log`; the container creates that
  directory at startup.
- The seeded config leaves `server.database.path` commented out, so
  `FILEBROWSER_DATABASE_PATH` (default
  `/config/filebrowser/db/filebrowser.sqlite`) selects the database file. A path
  set in `config.yaml` takes precedence over the variable.
- `ADDITIONAL_PARAMETERS` appends command line flags to the server start.
- An existing config written for an older release may be rejected by the current
  binary at startup. If that happens, fix or delete the config file to get a
  fresh seed.
- Full option reference:
  [FileBrowser Quantum configuration](https://filebrowserquantum.com/en/docs/configuration/)

### Environment variables

Supply secrets as environment variables rather than in the config file. Each
`FILEBROWSER_*` variable is passed to the server only when it holds a non-empty
value, so an empty or unset value leaves the matching config key in charge. A
non-empty secret variable overrides the matching key in `config.yaml`.

<!-- markdownlint-disable MD013 -->

| Variable | Default | Description |
| --- | --- | --- |
| `FILEBROWSER_ADMIN_PASSWORD` | - | Password for the `admin` account. Leave unset to have a random password generated and written to the log file once, with a password change forced at first login. When set, the value is applied on every start; the literal value `admin` is treated as unset. |
| `FILEBROWSER_JWT_TOKEN_SECRET` | - | Secret used to sign JWT authentication tokens. Changing it after first start invalidates all existing sessions. |
| `FILEBROWSER_TOTP_SECRET` | - | Encryption secret for stored TOTP two-factor secrets. Set it before enrolling users in TOTP. |
| `FILEBROWSER_RECAPTCHA_SECRET` | - | reCAPTCHA secret key, used by password authentication when reCAPTCHA is enabled. |
| `FILEBROWSER_LDAP_USER_PASSWORD` | - | Password of the LDAP bind account used to look up users. |
| `FILEBROWSER_OIDC_CLIENT_ID` | - | OIDC client id for single sign-on, for example from Authentik, Keycloak or Pocket ID. |
| `FILEBROWSER_OIDC_CLIENT_SECRET` | - | OIDC client secret for single sign-on. |
| `FILEBROWSER_ONLYOFFICE_SECRET` | - | JWT secret shared with your OnlyOffice document server. |
| `FILEBROWSER_DISABLE_AUTOMATIC_BACKUP` | `false` | Set to `true` to skip the automatic database backup taken before an upgrade. |
| `FILEBROWSER_CONFIG` | `/config/filebrowser/config/config.yaml` | Config file path. The default config is seeded here when the file is absent. |
| `FILEBROWSER_DATABASE_PATH` | `/config/filebrowser/db/filebrowser.sqlite` | SQLite database file, used when `server.database.path` is empty (the seeded default). A path set in `config.yaml` takes precedence. |
| `FILEBROWSER_FFMPEG_PATH` | `/usr/local/bin` | Directory holding the `ffmpeg` and `ffprobe` binaries. |
| `ADDITIONAL_PARAMETERS` | - | Additional command line flags appended to the server start. Wildcards are passed through literally. |
| `ENABLE_HEALTHCHECK` | `yes` | Healthchecks only run when set to `yes`; anything else, including unset, disables them. |
| `HEALTHCHECK_COMMAND` | - | Command or script to run instead of the default `healthcheck.sh` (process, DNS and HTTPS checks). |
| `HEALTHCHECK_ACTION` | - | Action to run when the healthcheck fails. Defaults to `exit 1`; use `kill 1` to stop the container. |
| `HEALTHCHECK_HOSTNAME` | `google.com` | Hostname used for the HTTPS and DNS checks. `HEALTHCHECK_HOSTNAMES` accepts several targets as a space or comma separated list. |
| `PUID` | `99` | User ID the container runs as. |
| `PGID` | `100` | Group ID the container runs as. |
| `UMASK` | `000` | Umask for files and directories the container creates. |

<!-- markdownlint-enable MD013 -->

The three path variables are optional: when unset the container uses the
defaults shown.

## Example

```bash
docker run -d \
        --name=filebrowser \
        -p 8125:8125 \
        -v /apps/docker/filebrowser:/config \
        -v /mnt/user:/media \
        -v /etc/localtime:/etc/localtime:ro \
        -e PUID=99 \
        -e PGID=100 \
        -e UMASK=000 \
        -e FILEBROWSER_ADMIN_PASSWORD=changeme \
        -e FILEBROWSER_CONFIG=/config/filebrowser/config/config.yaml \
        -e FILEBROWSER_DATABASE_PATH=/config/filebrowser/db/filebrowser.sqlite \
        -e FILEBROWSER_FFMPEG_PATH=/usr/local/bin \
        ghcr.io/binhex/arch-filebrowser-quantum
```

## Notes

- The `/media` mount is exposed as the `Media` source in `config.yaml`. Add
  further sources there, or change its `path` to suit your storage.
- TLS is not generated automatically. Configure `http.tlsCert` and
  `http.tlsKey` in `config.yaml` to serve HTTPS.

User ID (PUID) and Group ID (PGID) can be found by issuing the following
command for the user you want to run the container as:-

```bash
id <username>
```

___
If you appreciate my work, then please consider buying me a beer  :D

[![PayPal donation](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=MM5E27UX6AUU4)

[Documentation](https://github.com/binhex/documentation) | [Support forum](https://forums.unraid.net/topic/197257-support-binhex-file-browser/)
