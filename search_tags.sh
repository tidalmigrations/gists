#!/usr/bin/env bash

# TO USE - you must set:

#  SUBDOMAIN - to your Tidal Migrations account from get.tidalmg.com
#  API_TOKEN - to your Tidal Migrations account from guides.tidalmg.com/authenticate.html

SUBDOMAIN=SET_THIS
API_TOKEN=SET_THIS

curl -sS "https://$SUBDOMAIN.tidalmg.com/api/v1/tags?search=dev" -H "Authorization: Bearer $API_TOKEN" | jq .

# Use the result of this with the `fetch_ip_addresses.sh` script.
