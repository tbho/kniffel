#!/bin/sh

echo "Migrating..."
"$RELEASE_ROOT_DIR/bin/kniffel" migrate
