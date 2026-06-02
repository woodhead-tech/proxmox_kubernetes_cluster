# arr-stack: No Downloads After Rebuild (Stale Inter-Service API Keys)

**Date:** 2026-06-02
**Severity:** medium
**Affected:** arr-stack (LXC 202, 192.168.86.22) — Sonarr, Radarr, Prowlarr, SABnzbd

## Symptom

After the 2026-05-31 ground-up rebuild, the arr-stack containers were all `Up` and
the VPN/NFS were healthy, but **no downloads were happening**. SABnzbd queue was idle
with zero history ever. Searches in Sonarr/Radarr returned nothing.

## Root Cause

The rebuild restored containers and config files, but **every inter-service API key
was stale** (each service got a fresh key on rebuild, but the *stored copies* in the
other services still pointed at the old keys). Four independent breaks in the chain:

1. **Sonarr → SABnzbd**: Sonarr's download-client API key was wrong. SAB logged
   repeating `API key incorrect ... [Sonarr]` warnings; connectivity test returned HTTP 400.
   (Radarr's SAB key happened to be correct.)
2. **SABnzbd folders reset to defaults**: `download_dir`/`complete_dir` were *relative*
   (`Downloads/incomplete`, `Downloads/complete`) → resolved under `/config` (LXC local
   disk, 19.5 GB) instead of the `/downloads` NFS mount (5.4 TB). SAB reported only
   19.5 GB total. Sonarr/Radarr also threw a remote-path-mapping health error.
3. **Prowlarr → Radarr/Sonarr** (Applications): Prowlarr held stale *app* API keys →
   "API Key is invalid" on application test → no indexer sync.
4. **Radarr/Sonarr → indexer**: the synced "NZBgeek (Prowlarr)" indexer in each app
   carried a stale *Prowlarr* API key → "Unable to connect to indexer, invalid
   credentials." This is why searches found nothing. (The "all indexers unavailable for
   6 hours" health errors were a stale side effect, not the cause — direct indexer test
   in Prowlarr passed.)

## Diagnosis

```bash
ssh -i ~/.ssh/id_ansible root@192.168.86.22

# SAB key + queue/history (note: SAB runs inside gluetun netns; use docker exec gluetun)
API=$(grep -E "^api_key" /opt/arr/sabnzbd/config/sabnzbd.ini | head -1 | awk "{print \$3}")
docker exec gluetun wget -qO- "http://localhost:8080/api?mode=queue&output=json&apikey=$API"   # status: Idle, 0 slots
docker exec gluetun wget -qO- "http://localhost:8080/api?mode=warnings&output=json&apikey=$API" # "API key incorrect [Sonarr]"
docker exec gluetun wget -qO- "http://localhost:8080/api?mode=get_config&section=misc&apikey=$API" # relative dirs

# App keys live in config.xml; test each link
# get key:  grep -oP "(?<=<ApiKey>)[^<]+" /opt/arr/<svc>/config/config.xml
# Sonarr->SAB:  POST /api/v3/downloadclient/test     -> 400
# Prowlarr->app: POST /api/v1/applications/test       -> "API Key is invalid"
# app->indexer:  POST /api/v3/indexer/test            -> "invalid credentials"

# Confirm the Prowlarr proxy itself works (isolates key vs connectivity):
PK=$(grep -oP "(?<=<ApiKey>)[^<]+" /opt/arr/prowlarr/config/config.xml)
docker exec sonarr wget -qO- "http://192.168.86.22:9696/1/api?apikey=$PK&t=caps"   # returns valid <caps> XML
```

Decisive tell: grab history in Sonarr/Radarr was dated weeks before the rebuild
(Apr 30 / May 22), proving fresh searches grabbed nothing — point at the indexer link.

## Fix

All fixes done via each service's REST API (PUT the object with the corrected key field,
then POST .../test). SAB folder change uses the SAB `set_config` API (applies live, no restart).

```bash
# 1. SABnzbd folders -> NFS (the /downloads/{incomplete,complete} dirs already exist)
docker exec gluetun wget -qO- "http://localhost:8080/api?apikey=$API&mode=set_config&section=misc&keyword=download_dir&value=/downloads/incomplete"
docker exec gluetun wget -qO- "http://localhost:8080/api?apikey=$API&mode=set_config&section=misc&keyword=complete_dir&value=/downloads/complete"

# 2. Sonarr -> SABnzbd: set download client apiKey field to SAB's real api_key, PUT, test

# 3. Prowlarr -> apps: set each Application's apiKey to the current Sonarr/Radarr key
#    (from config.xml), PUT, test, then trigger sync:
#    POST /api/v1/command {"name":"ApplicationIndexerSync"}

# 4. Radarr/Sonarr -> indexer: ApplicationIndexerSync did NOT overwrite the existing
#    indexer's stale key. Set the app indexer's apiKey field directly to the CURRENT
#    Prowlarr key, PUT /api/v3/indexer/<id>, test.
```

Key mapping (each service's real key lives in its own config):
- SAB:     `grep ^api_key /opt/arr/sabnzbd/config/sabnzbd.ini`
- Others:  `grep -oP "(?<=<ApiKey>)[^<]+" /opt/arr/<sonarr|radarr|prowlarr>/config/config.xml`

## Verification

```bash
# All link tests should return 200/PASS:
#   Sonarr->SAB, Radarr->SAB, Prowlarr->Radarr, Prowlarr->Sonarr, app->indexer (both)

# End-to-end: trigger a search and watch SAB actually download
RK=$(grep -oP "(?<=<ApiKey>)[^<]+" /opt/arr/radarr/config/config.xml)
docker exec radarr wget -qO- --post-data='{"name":"MissingMoviesSearch"}' \
  --header="X-Api-Key: $RK" --header="Content-Type: application/json" \
  http://localhost:7878/api/v3/command
sleep 20
docker exec gluetun wget -qO- "http://localhost:8080/api?mode=queue&output=json&apikey=$API"
# Expect: status "Downloading", items > 0, speed > 0.
```

Confirmed 2026-06-02: SAB pulling 6 items at ~27 MB/s onto the NFS.

## Prevention / Mitigations

- **After any arr-stack rebuild, re-validate every inter-service link, not just that
  containers are Up.** "All containers running" hides stale-key breakage completely.
- Run all five link tests above as a post-rebuild smoke check.
- Consider pinning API keys in the rebuild config (env/Ansible) so a rebuild reuses the
  same keys instead of regenerating them — would eliminate this entire failure class.
- SAB folders must be absolute (`/downloads/...`), never relative, or downloads land on
  the LXC local disk instead of the NFS.

## Notes

- SABnzbd runs inside gluetun's network namespace — query its API via
  `docker exec gluetun wget -qO- "http://localhost:8080/api?..."`, not directly.
- `ApplicationIndexerSync` updates Prowlarr↔app linkage but did **not** rewrite the
  apiKey on an already-existing app-side indexer; that had to be set directly.
- Related: seerr (overseerr) was uninitialized after the rebuild — Radarr/Sonarr were
  re-wired via its API, but it still needs the Plex setup wizard run once to create the
  admin account.
- Follow-up: only NZBgeek indexer configured — Kanboard Engineering task #148 to add more.
</content>
</invoke>
