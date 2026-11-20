#!/bin/sh
# Deterministic 12-char SHA1 build fingerprint of routine code & container definition
cd "${1:-.}" || exit 1
if   command -v sha1sum >/dev/null 2>&1; then H=sha1sum
elif command -v shasum  >/dev/null 2>&1; then H=shasum
elif command -v openssl >/dev/null 2>&1; then H="openssl dgst -sha1 -r"
else echo "NO-HASH-TOOL"; exit 0; fi

files="$(find Dockerfile entrypoint.sh init.R main_pasture.R main.R user_config_TEMPLATE.R config/knobs.json codes external/cascade-core tools -type f \( -name '*.R' -o -name '*.sh' -o -name '*.json' -o -name '*.csv' -o -name '*.cpp' -o -name '*.h' -o -name 'Dockerfile' -o -name 'DESCRIPTION' -o -name 'NAMESPACE' \) 2>/dev/null | LC_ALL=C sort)"
id="$(cat $files 2>/dev/null | $H | cut -c1-12)"
case "$id" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) echo "$id" ;;
  *) echo "UNHASHABLE" ;;
esac

