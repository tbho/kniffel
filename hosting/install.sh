#!/usr/bin/env bash
set -euo pipefail

ssh $1 "mkdir -p /root/kniffel"
scp app.env $1:/root/kniffel/app.env
scp db.env $1:/root/kniffel/db.env
scp docker-compose.yml $1:/root/kniffel/docker-compose.yml

scp -r setup/ $1: && ssh $1 "cd ~/setup; chmod +x setup.sh; ./setup.sh"
scp nginx/nginx.conf $1:/etc/nginx/sites-available/default && ssh $1 "sudo service nginx restart"
