#!/bin/bash

sed -i "s/\$SENTINEL_PORT/$SENTINEL_PORT/g" /data/sentinel.conf

exec "$@"