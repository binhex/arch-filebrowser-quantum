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
        -e PUID=<uid for user> \
        -e PGID=<gid for user> \
        -e UMASK=<umask for created files> \
        -e ADDITIONAL_PARAMETERS=<cli options> \
        -e FILEBROWSER_ADMIN_PASSWORD=<admin password> \
        -e ENABLE_HEALTHCHECK=<yes|no> \
        -e HEALTHCHECK_COMMAND=<command> \
        -e HEALTHCHECK_ACTION=<action> \
        -e HEALTHCHECK_HOSTNAME=<hostname> \
        ghcr.io/binhex/arch-filebrowser-quantum
```

Please replace all user variables in the above command defined by <> with the
correct values.

## Access application

`http://<host ip>:8125`

Default username/password: `admin/admin`. Set `FILEBROWSER_ADMIN_PASSWORD` to
choose your own; a value shorter than 8 characters is rejected when an admin
account already exists (the previous password is kept), while a fresh install
accepts the first value. Releases from v2.0.9 onwards generate a random admin
password and print it in the container log on first start, so check the log if
`admin/admin` is rejected.

## Configuration

On first start the container seeds a commented reference configuration to
`/config/config.yaml`. Only the basics are active: the webui port, the `/media`
source, the cache and database locations, and password authentication. Every
other option is present but commented out - uncomment the ones you need and
restart the container.

- The file is seeded whenever `/config/config.yaml` is absent or empty. An
  existing config is never overwritten, so your edits survive a restart.
- Installs created before this change keep working: a config at
  `/config/filebrowser/config/config.yaml` is copied to the new location, and
  the old file is kept as a backup. Remove it once the container starts
  cleanly - while it exists, deleting `/config/config.yaml` re-imports it
  instead of re-seeding.
- Installing with `FILEBROWSER_DATABASE_PATH` set to a location other than
  `/config/filebrowser/database.sqlite` needs one edit: the seeded config sets
  `server.database.path`, which takes precedence, so point it at your existing
  database file or delete that key. The container logs a warning when it seeds
  a config while the variable is set, because otherwise the server starts on a
  new empty database and your users and shares appear to be missing.
- At startup the container removes leftover `/config/config.yaml.tmp.*`
  temporary files older than five minutes - do not store anything under that
  name.
- A migrated config written for an older release may be rejected by the current
  binary at startup. If that happens, fix or delete `/config/config.yaml` and
  remove the legacy file to get a fresh seed.
- `ADDITIONAL_PARAMETERS` appends command line flags to the server start.
- Full option reference:
  [FileBrowser Quantum configuration](https://filebrowserquantum.com/en/docs/configuration/)

Supply secrets as environment variables rather than in the config file.
`FILEBROWSER_CONFIG` is ignored: the container always passes `--config` with
`/config/config.yaml`. These environment variables are passed through to the
server:

`FILEBROWSER_ADMIN_PASSWORD`, `FILEBROWSER_JWT_TOKEN_SECRET`,
`FILEBROWSER_TOTP_SECRET`, `FILEBROWSER_RECAPTCHA_SECRET`,
`FILEBROWSER_LDAP_USER_PASSWORD`, `FILEBROWSER_OIDC_CLIENT_ID`,
`FILEBROWSER_OIDC_CLIENT_SECRET`, `FILEBROWSER_ONLYOFFICE_SECRET`,
`FILEBROWSER_FFMPEG_PATH`, `FILEBROWSER_DISABLE_AUTOMATIC_BACKUP`. Each is passed
to the server only when it holds a non-empty value, so an empty or unset value
leaves the matching config key in charge.

`server.database.path` in `config.yaml` takes precedence over
`FILEBROWSER_DATABASE_PATH` - remove that key if you prefer the variable.

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
        ghcr.io/binhex/arch-filebrowser-quantum
```

## Notes

- The `/media` mount is exposed as the `Media` source in `config.yaml`. Add
  further sources there, or change its `path` to suit your storage.
- TLS is not generated automatically. Configure `http.tlsCert` and
  `http.tlsKey` in `config.yaml` to serve HTTPS.
- Healthchecks are controlled by `ENABLE_HEALTHCHECK`, `HEALTHCHECK_COMMAND`,
  `HEALTHCHECK_ACTION` and `HEALTHCHECK_HOSTNAME` (or
  `HEALTHCHECK_HOSTNAMES`).

User ID (PUID) and Group ID (PGID) can be found by issuing the following
command for the user you want to run the container as:-

```bash
id <username>
```

___
If you appreciate my work, then please consider buying me a beer  :D

[![PayPal donation](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=MM5E27UX6AUU4)

[Documentation](https://github.com/binhex/documentation) | [Support forum](https://forums.unraid.net/topic/197257-support-binhex-file-browser/)
