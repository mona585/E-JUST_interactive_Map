# Credential Rotation Handoff

This file identifies the credentials removed during recovery Phase 0. It does
not contain secret values.

## Google Maps and Directions API keys

**Where to obtain them:** the E-JUST Google Cloud organization, under the
project selected by the university administrator:
`APIs & Services` → `Credentials`.

Create separate restricted keys for:

- Browser Maps JavaScript API — restrict to the official E-JUST web origins.
- Android Maps/Directions — restrict to the new E-JUST package IDs and signing
  certificate fingerprints established in ADR 0001.

Disable or delete the old keys that were committed to this repository. Do not
place replacements in source files; Phase 4/8 will define the parameterised
client configuration and production injection procedure.

## Play/application secret

**Where to install it:** the Ubuntu production or staging VM, in
`/etc/anyplace/anyplace.env`.

Generate a new high-entropy value on the Linux host, then create the file as
root with these permissions:

```bash
sudo install -d -m 700 /etc/anyplace
sudo sh -c 'umask 077; printf "APPLICATION_SECRET=<new-secret>\\n" > /etc/anyplace/anyplace.env'
sudo chmod 600 /etc/anyplace/anyplace.env
```

The service template reads this file through `EnvironmentFile`. Restarting the
service with a new value invalidates existing server sessions; this is expected
for rotation.

## Repository history

The old values may remain in Git history even though they are removed from the
current checkout. Rotate or revoke them first. A repository administrator can
then decide whether history rewriting and forced pushes are appropriate for the
remote(s) that received the exposure.

## Ownership checklist

- University Google Cloud administrator: issue restricted keys and revoke old
  keys.
- University Linux administrator: create `/etc/anyplace/anyplace.env` with a
  new secret and restart only during a planned maintenance window.
- Repository administrator: confirm which remotes contain the prior commits and
  decide on history cleanup after rotation.
