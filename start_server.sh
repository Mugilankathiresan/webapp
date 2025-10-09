#!/usr/bin/env bash
set -e
cp -r /tmp/deploy/* /usr/share/nginx/html/ || true
systemctl restart nginx || true
