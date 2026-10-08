#!/bin/bash
cd /home/container || exit 1

# Everything SeaweedFS stores (volumes, master and filer metadata) lives here.
mkdir -p /home/container/data

MASTER=127.0.0.1:19333
FILER=127.0.0.1:18888

# No keys, no server: an S3 endpoint without credentials would either refuse
# every request or, worse, accept anonymous ones.
if [ -z "${S3_ACCESS_KEY:-}" ] || [ -z "${S3_SECRET_KEY:-}" ]; then
    echo "Renode: S3_ACCESS_KEY and S3_SECRET_KEY must both be set. Not starting."
    exit 1
fi

# The identity file is rewritten on every start from the server's variables,
# and kept out of the volume so the file manager never shows a stale copy.
cat > /tmp/renode-s3.json <<JSON
{
  "identities": [
    {
      "name": "admin",
      "credentials": [{ "accessKey": "${S3_ACCESS_KEY}", "secretKey": "${S3_SECRET_KEY}" }],
      "actions": ["Admin", "Read", "Write", "List", "Tagging"]
    }
  ]
}
JSON
chmod 600 /tmp/renode-s3.json

# Pterodactyl startup: {{VAR}} -> ${VAR}. The string is run as a script, not
# expanded through `eval echo` first: the panel may prefix it with commands of
# its own (a console banner), and `eval echo` would run those inside a command
# substitution and hand their output back as the command to execute.
MODIFIED_STARTUP=$(printf '%s' "${STARTUP:-weed server -dir=/home/container/data -s3}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo ":/home/container$ ${MODIFIED_STARTUP}"

# Own session, so shutdown can signal bash and weed together. stdin stays
# with this script: console lines are weed shell commands, read below.
setsid bash -c "${MODIFIED_STARTUP}" </dev/null &
PID=$!

shutdown() {
    echo "Stopping SeaweedFS..."
    kill -TERM -- "-$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null
    wait "$PID"
    exit $?
}
trap shutdown INT TERM

weed_shell() {
    printf '%s\n' "$1" | weed shell -master="$MASTER" -filer="$FILER" 2>&1
}

# The customer's bucket, created once the filer answers. Idempotent, so this
# runs on every start. The name is checked against S3's own rules first.
provision() {
    local bucket="${S3_BUCKET:-}"
    [ -z "$bucket" ] && return 0
    if ! [[ "$bucket" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
        echo "Renode: S3_BUCKET '${bucket}' is not a valid bucket name; not created."
        return 0
    fi
    for _ in $(seq 1 90); do
        curl -s -o /dev/null "http://${FILER}/" && break
        kill -0 "$PID" 2>/dev/null || return 0
        sleep 2
    done
    for _ in $(seq 1 15); do
        if weed_shell "s3.bucket.list" | grep -qE "^[[:space:]]*${bucket}([[:space:]]|$)"; then
            echo "Renode: Bucket ${bucket} is ready."
            return 0
        fi
        weed_shell "s3.bucket.create -name ${bucket}" >/dev/null
        if weed_shell "s3.bucket.list" | grep -qE "^[[:space:]]*${bucket}([[:space:]]|$)"; then
            echo "Renode: Created bucket ${bucket}."
            return 0
        fi
        sleep 2
    done
    echo "Renode: Could not create bucket ${bucket}."
}
provision &

# Panel console lines run as `weed shell` commands. In the background, so the
# container lives exactly as long as SeaweedFS does: a server that fails to
# start must exit, or Wings shows "starting" for ever. stdin is passed
# explicitly; a background job would otherwise get /dev/null.
exec 3<&0
while IFS= read -r line <&3; do
    [ -z "$line" ] && continue
    weed_shell "$line" || true
done &

wait "$PID"
exit $?
