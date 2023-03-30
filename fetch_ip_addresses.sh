#!/usr/bin/env bash

# TO USE - you must set:

#  SUBDOMAIN - To your Tidal account from get.tidalmg.com
#  API_TOKEN - To your Tidal account from guides.tidalmg.com/authenticate.html
#  TAG_ID    - Set this to the tag you want to use, that is returned from the `search_tags.sh` script

SUBDOMAIN=SET_THIS
API_TOKEN=SET_THIS
TAG_ID=SET_THIS

# The results will be in a text file, `ip_addresses.txt`

# Get all the applications with that tag:
app_ids=$(curl -sS "https://$SUBDOMAIN.tidalmg.com/api/v1/apps?tag_id=$TAG_ID" -H "Authorization: Bearer $API_TOKEN" | jq ".[] | .id" )

# 3 - For each app ID get all the dependencies for each application
server_ids=()
while IFS= read -r id ; do
  server_ids+=$(curl -sS "https://$SUBDOMAIN.tidalmg.com/api/v1/apps/$id/dependencies" -H "Authorization: Bearer $API_TOKEN" | jq '.children | .[] | select(.type == "Server") | .id')
done <<< "$app_ids"

# Format ids
server_ids=$(echo $server_ids | jq -Rr 'gsub(" "; "\n")')

# 4 - For each server dependencies for the application, get all it's IP addresses
ip_addresses=()
while IFS= read -r id ; do
  ip_addresses+=$(curl -sS "https://$SUBDOMAIN.tidalmg.com/api/v1/servers/$id" -H "Authorization: Bearer $API_TOKEN"  | jq '.ip_addresses | .[] | .address')
done <<< "$server_ids"

# Format ids
ip_addresses=$(echo $ip_addresses | jq -Rr 'gsub(" "; "\n")')

echo "All the IP addresses for given tag, are in the file: ip_addresses.txt"
echo $ip_addresses > ip_addresses.txt
