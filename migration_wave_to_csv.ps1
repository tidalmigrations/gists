# $username = ""
# $password = ""
# $move_group_id = ""
# $subdomain = ""

$body = @{
    "username" = $username
    "password" = $password
}

$access_token = Invoke-WebRequest -Uri "https://${subdomain}.tidal.cloud/api/v1/authenticate" -Method "Post" `
                                  -Body ($body|ConvertTo-Json) -ContentType "application/json" `
                | ConvertFrom-Json `
                | Select -ExpandProperty access_token

$auth = @{"Authorization" = "Bearer ${access_token}";}

$servers = Invoke-WebRequest -Uri "https://${subdomain}.tidal.cloud/api/v1/move_groups/${move_group_id}" -Method "Get" `
                             -Headers $auth -ContentType "application/json" `
           | ConvertFrom-Json `
           | Select-Object -Expand servers `
           | Select-Object -Property host_name,
                                     @{Name = 'username';   Expression = { $_.custom_fields.username }}, `
                                     @{Name = 'password';   Expression = { $_.custom_fields.password }}, `
                                     @{Name = 'domain';   Expression = { $_.custom_fields.domain }} `

echo $servers | ConvertTo-Csv
