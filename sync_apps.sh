# REQUIREMENTS
#
# In order to use requires;
# 1. miller -https://miller.readthedocs.io/en/6.9.0/installing-miller/
# 2. and jq - https://jqlang.github.io/jq/download/
# 3. tidal - https://get.tidal.sh
# 4. tidal CLI must be authenticated to the Tidal Accelerator API, ie. `tidal login`


# USAGE
#
# To use, it will take a csv file from standard input;
# `cat app_costs.csv | ./sync_apps.sh`


# CSV INPUT FORMAT
#
# CSV should be a list of app records, where one column is 'name' of the app, and others are either app attributes or custom fields.
# A sample and usable CSV file is below. 'name' of app column is required'.
# 'annual_hosting_costs' is an attribute of apps in Accelerator API, and optional.
# All other fields are custom fields.

# name,annual_hosting_costs,projected_hosting_if_rehosted,projected_hosting_if_rehosted_with_db_replatform,projected_hosting_if_refactored
# Chat Server,"135",45,45,0
# Documentation Server,"162",351,351,0
# Geoserver,"186","1346","174",0
# Request Tracker,"136","100","2095",0


# CUSTOM FIELDS CONFIGURATION
#
# Any column headers that are custom fields need to be assigned here.
# If there are more than 3, you must extend the commands below appropriately.
custom_1=projected_hosting_if_rehosted
custom_2=projected_hosting_if_rehosted_with_db_replatform
custom_3=projected_hosting_if_refactored


mlr --icsv --ojson cat | jq --arg custom_1 "$custom_1" --arg custom_2 "$custom_2" --arg custom_3 "$custom_3" \
					   '. as $input | .custom_fields = {($custom_1): $input[$custom_1],
                                                                            ($custom_2): $input[$custom_2],
									    ($custom_3): $input[$custom_3]}
					    | del(.[$custom_1], .[$custom_2], .[$custom_3])' \
				     |  jq -s '{ "apps": . }' \
				     | tidal sync apps
