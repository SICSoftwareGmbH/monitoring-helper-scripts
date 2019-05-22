#!/bin/sh
# Use latest version of sensu-sic-handler from asset cache to import data from redmine
#
# Author: Florian Schwab <florian.schwab@sic.software>

latestBin=$(ls -t /var/cache/sensu/sensu-backend/*/bin/sensu-sic-handler 2>/dev/null | head -n1)

if [ ! -z "${latestBin}" ]; then
  $latestBin redmine import -c /etc/sensu/sic-handler.yml
fi
