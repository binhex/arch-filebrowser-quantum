#!/usr/bin/dumb-init /bin/bash
# shellcheck shell=bash

# no config bind mount
if [[ ! -d "/config" ]]; then
	echo "[crit] /config bind mount not found, exiting..." ; exit 1
fi

# define config and data paths
data_root="/config/filebrowser/config"
config_file="${data_root}/config.yaml"
seed_config_file="/opt/filebrowser/config.default.yaml"
filebrowser_install_path="/opt/filebrowser"

# create data path, used for the cache and the database
if ! mkdir -p "${data_root}"; then
	echo "[crit] Failed to create '${data_root}', exiting..." ; exit 1
fi

# remove any temporary file left behind by an interrupted earlier start
for stale_config_file in "${config_file}".tmp.*; do
	if [[ ! -f "${stale_config_file}" ]]; then
		continue
	fi
	# only sweep files old enough to belong to an earlier start, never another
	# instance's in-flight temporary file
	if [[ -z "$(find "${stale_config_file}" -mmin +5 -print -quit 2>/dev/null)" ]]; then
		continue
	fi
	if rm -f "${stale_config_file}"; then
		echo "[warn] Removed leftover temporary config '${stale_config_file}'."
	else
		echo "[warn] Could not remove leftover temporary config '${stale_config_file}'."
	fi
done

# seed or migrate the config on first run, an existing config is never overwritten
if [[ -d "${config_file}" ]]; then
	echo "[crit] '${config_file}' is a directory, expected a file, exiting..." ; exit 1
fi

if [[ ! -s "${config_file}" ]]; then
	if [[ -s "${seed_config_file}" ]]; then
		echo "[info] Seeding default config to '${config_file}'..."
		source_config_file="${seed_config_file}"
	else
		echo "[crit] No usable config at '${config_file}' and no seed at '${seed_config_file}', exiting..." ; exit 1
	fi

	# copy to a unique temporary file and move it into place, so an interrupted
	# copy can never be mistaken for a valid config on the next start
	if ! temporary_config_file="$(mktemp "${config_file}.tmp.XXXXXX")"; then
		echo "[crit] Failed to create a temporary file next to '${config_file}', exiting..." ; exit 1
	fi
	if [[ "${source_config_file}" == "${seed_config_file}" ]]; then
		# mktemp creates the file 0600, open it to 0644 so the operator can read and edit it
		copy_options=()
		permissions="0644"
	else
		# keep the mode the operator's existing config already had, without trying
		# to preserve ownership, which can fail when running as root
		copy_options=(-p --no-preserve=ownership)
		permissions="u+rw"
	fi
	if ! cp "${copy_options[@]}" "${source_config_file}" "${temporary_config_file}"; then
		rm -f "${temporary_config_file}"
		echo "[crit] Failed to copy '${source_config_file}' to '${temporary_config_file}', exiting..." ; exit 1
	fi
	if ! chmod "${permissions}" "${temporary_config_file}"; then
		rm -f "${temporary_config_file}"
		echo "[crit] Failed to set permissions on '${temporary_config_file}', exiting..." ; exit 1
	fi
	if ! mv "${temporary_config_file}" "${config_file}"; then
		rm -f "${temporary_config_file}"
		echo "[crit] Failed to move '${temporary_config_file}' into place, exiting..." ; exit 1
	fi

fi

# export env vars, each only when non-empty: an empty value would otherwise
# override or disable the matching config-file option
# shellcheck disable=SC2163
for env_var in \
	FILEBROWSER_ADMIN_PASSWORD \
	FILEBROWSER_JWT_TOKEN_SECRET \
	FILEBROWSER_TOTP_SECRET \
	FILEBROWSER_RECAPTCHA_SECRET \
	FILEBROWSER_LDAP_USER_PASSWORD \
	FILEBROWSER_OIDC_CLIENT_ID \
	FILEBROWSER_OIDC_CLIENT_SECRET \
	FILEBROWSER_ONLYOFFICE_SECRET \
	FILEBROWSER_CONFIG \
	FILEBROWSER_DATABASE_PATH \
	FILEBROWSER_FFMPEG_PATH \
	FILEBROWSER_DISABLE_AUTOMATIC_BACKUP; do
	if [[ -n "${!env_var}" ]]; then
		export "${env_var}"
	else
		unset "${env_var}"
	fi
done

# export any additional parameters
export ADDITIONAL_PARAMETERS="${ADDITIONAL_PARAMETERS}"

# disable pathname expansion so a wildcard in ADDITIONAL_PARAMETERS reaches the
# server unchanged
set -f

# run filebrowser with appropriate options
# ${ADDITIONAL_PARAMETERS} is intentionally unquoted so several flags can be passed
# shellcheck disable=SC2086
"${filebrowser_install_path}/filebrowser" \
	--config "${config_file}" \
	${ADDITIONAL_PARAMETERS}
