#!/bin/sh
set -e

# First boot on a fresh volume: create the schema, load the catalogues and draw
# the placeholder artwork. Both steps are idempotent (upserts), so this is safe
# to run on every start — it will not overwrite live data or re-add deleted rows.
if [ "${SKIP_SEED}" != "1" ]; then
  echo "→ applying schema and seeding catalogues"
  node server/src/seed.js || echo "  (seed skipped: $?)"

  if [ ! -f "${DATA_DIR:-/data}/.placeholders-generated" ]; then
    echo "→ generating placeholder badge/award artwork (first run only)"
    node server/scripts/generate-placeholders.js \
      && touch "${DATA_DIR:-/data}/.placeholders-generated"
  fi
fi

exec "$@"
