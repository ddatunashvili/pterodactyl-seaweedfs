# Pterodactyl SeaweedFS (S3) egg

S3-compatible object storage for Pterodactyl, built on [SeaweedFS](https://github.com/seaweedfs/seaweedfs) 4.48.

## Image

`ghcr.io/ddatunashvili/pterodactyl-seaweedfs:latest` (plus a `sha-<commit>` tag), built by
`.github/workflows/docker.yml` on every push to `main`. The workflow boots the image the way
Wings does (uid 988, Wings' dropped capabilities, `no-new-privileges`, tmpfs `/tmp`, a
banner-prefixed startup line) and only pushes if S3 accepts the right keys, refuses wrong and
anonymous ones, round-trips an object and keeps it across a restart.

## How it runs

One `weed server` process: master, volume, filer and the S3 gateway. Only S3 is public, on the
server's allocation (`SERVER_PORT`). Everything else binds to `127.0.0.1` on fixed internal
ports (19333, 18080, 18888, gRPC 29333/28080/28888/18333), which live in the container's own
network namespace and cannot collide with allocations. All data is under
`/home/container/data`, so panel backups include it.

## Egg

Import `egg-seaweedfs.json` (Admin > Nests > Import Egg).

| Variable | Notes |
|---|---|
| `S3_ACCESS_KEY` | required, 16-40 alphanumerics |
| `S3_SECRET_KEY` | required, 32-64 alphanumerics. The server refuses to start without both keys |
| `S3_BUCKET` | created on start if missing (default `default`) |
| `VOLUME_SIZE_MB` | volume file size, default 1024 |

Connect with endpoint `http://<node-ip>:<port>`, path-style addressing, any region:

```bash
aws --endpoint-url http://<node-ip>:<port> s3 ls
```

Lines typed in the panel console run as `weed shell` commands (e.g. `s3.bucket.list`).

Plain HTTP: put the panel's proxy in front of it for HTTPS.
