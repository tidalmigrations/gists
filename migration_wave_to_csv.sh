#!/bin/bash
access_token=$(curl -H Content-Type\:\ application/json -XPOST https\://$subdomain.tidal.cloud/api/v1/authenticate -d \{\"username\"\:\ \"$username\"\,\ \"password\"\:\ \"$password\"\} | jq '.access_token' | sed 's/"//g')

move_group=$(curl -H Authorization\:\ \"Bearer\ $access_token\" -H Content-Type\:\ application/json -XGET https\://$subdomain.tidal.cloud/api/v1/move_groups/$migration_wave_id | jq '.servers')

echo "hostname, username, password, domain"
echo $move_group | jq -M -r '.[] | .host_name as $h | .custom_fields | [$h, .username, .password, .domain] | @csv'
