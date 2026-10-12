#!/bin/sh
printenv > /etc/environment
exec "$@"