#!/usr/bin/env ruby
module AzureAppServiceApi
  require "net/http"

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/resources/resource-groups/list?view=rest-resources-2021-04-01
  def list_resource_groups(subscription)
    azure_request("#{base_sub(subscription)}/resourcegroups", :get, "2023-07-01")["value"]
  end

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/list?view=rest-appservice-2022-03-01
  def list_app_services(subscription, resource_group)
    azure_site(subscription, resource_group, "/", :get, "2022-09-01")["value"]
  end

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/get?view=rest-appservice-2022-03-01
  def get_app_service(subscription, name, resource_group)
    azure_site(subscription, resource_group, "/#{name}")
  end

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/list-connection-strings?view=rest-appservice-2022-03-01
  def list_connection_strings(subscription, resource_group, app_name)
    azure_site(subscription, resource_group, "#{app_name}/config/connectionstrings/list", :post)
  end

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/list-application-settings?view=rest-appservice-2022-03-01
  def list_app_settings(subscription, resource_group, app_name)
    azure_site(subscription, resource_group, "/#{app_name}/config/appsettings/list", :post)
  end

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/sql/managed-instances/list?view=rest-sql-2021-11-01&tabs=HTTP
  def list_database_managed_instances(subscription)
    azure_request "#{base_sub(subscription)}/providers/Microsoft.Sql/managedInstances", :get, "2021-11-01"
  end

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/sql/servers/list?view=rest-sql-2021-11-01&tabs=HTTP
  def list_database_servers(subscription)
    azure_request "#{base_sub(subscription)}/providers/Microsoft.Sql/servers", :get, "2021-11-01"
  end

  # API Documentation -
  # https://learn.microsoft.com/en-us/rest/api/postgresql/flexibleserver/servers/list?view=rest-postgresql-flexibleserver-2022-12-01&tabs=HTTP
  def list_postgres_flexible_servers(subscription)
    azure_request "#{base_sub(subscription)}/providers/Microsoft.DBforPostgreSQL/flexibleServers", :get, "2022-12-01"
  end

  # API Documentation -
  # https://learn.microsoft.com/en-us/rest/api/mysql/flexibleserver/servers/list?view=rest-mysql-flexibleserver-2023-06-01-preview&tabs=HTTP
  def list_mysql_flexible_servers(subscription)
    azure_request "#{base_sub(subscription)}/providers/Microsoft.DBforMySQL/flexibleServers", :get, "2023-06-01-preview"
  end

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/redis/redis/list?view=rest-redis-2018-03-01&tabs=HTTP
  def list_redis_databases(subscription)
    azure_request "#{base_sub(subscription)}/providers/Microsoft.Cache/Redis", :get, "2018-03-01"
  end

  # API Documentation - https://learn.microsoft.com/en-us/rest/api/appservice/app-service-plans/get?view=rest-appservice-2022-03-01&tabs=HTTP
  def app_service_service_plan(app_service)
    azure_request app_service["properties"]["serverFarmId"]
  end

  # Makes a request to Azure API at a base path of:
  # /subscriptions/:id/resourceGroups/:name/providers/Microsoft.Web/sites
  def azure_site(subscription, resource_group, path, method = :get, version = "2022-03-01")
    azure_request "#{base_site(subscription, resource_group)}/#{path}", method, version
  end

  def base_site(subscription, resource_group)
    "#{base_rg(subscription, resource_group)}/sites"
  end

  def base_rg(subscription, resource_group)
    "#{base_sub(subscription)}/resourceGroups/#{resource_group}/providers/Microsoft.Web"
  end

  def base_sub(subscription)
    "/subscriptions/#{subscription}"
  end

  def azure_request(path, method = :get, version = "2022-03-01")
    JSON.parse(make_request(method:       method,
                            path:         "https://management.azure.com#{path}",
                            body:         nil,
                            query_params: { "api-version": version },
                            headers:      { "Authorization" => "Bearer #{ENV.fetch('AZURE_TOKEN')}" }).response.body)
  end

  def make_request(method:,path:, query_params: {}, body: {}, headers: {}, form: [], ssl: true, timeout: 60, basic_auth: [])
    uri, http = get_uri_http(path:         path,
                             ssl:          ssl,
                             query_params: query_params)
    request = Object.const_get("Net::HTTP::#{method.downcase.capitalize}").new(uri.request_uri)
    request.basic_auth(*basic_auth) unless basic_auth.empty?

    if form || form.empty?
      request.body = body
    else
      request.set_form(*form)
    end

    http.read_timeout = timeout
    headers.each { |k, v| request[k] = v }

    http.request(request)
  end

  def get_uri_http(path:, query_params: nil, ssl: true)
    uri = URI(path)
    uri.query = URI.encode_www_form query_params if query_params
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = ssl
    [uri, http]
  end
end

module AzureAppServiceDetails
  require "fileutils"
  require "json"
  include AzureAppServiceApi

  def required_role_json
    <<~ROLE
      {
          "properties": {
              "roleName": "AppServiceAndDatabasesRead",
              "description": "Read access to several Databases resources, and App Services including sensitive information.",
              "assignableScopes": [
                  "/subscriptions/ADD-SUBSCRIPTION-ID-HERE"
              ],
              "permissions": [
                  {
                      "actions": [
                          "Microsoft.Resources/subscriptions/resourceGroups/read",
                          "Microsoft.Web/sites/Read",
                          "Microsoft.Web/sites/config/list/Action",
                          "Microsoft.Web/serverfarms/Read",
                          "Microsoft.Sql/managedInstances/read",
                          "Microsoft.Sql/servers/read",
                          "Microsoft.DBforPostgreSQL/flexibleServers/read",
                          "Microsoft.DBforMySQL/flexibleServers/read",
                          "Microsoft.Cache/redis/read"
                      ],
                      "notActions": [],
                      "dataActions": [],
                      "notDataActions": []
                  }
              ]
          }
      }
    ROLE
  end

  def all_app_services(subscription)
    list_resource_groups(subscription).map do |resource_group|
      list_app_services(subscription, resource_group["name"])
    end.flatten
  end

  # Given a string will return the string up to the first , or ; character.
  # Another option is to target passwords specifically with something such as "(.*?),password(.*)"
  def remove_passwords(input)
    matches = input.match("(.*?)[,;](.*)")
    matches ? matches[1] : input
  end

  def redact_app_settings(app_settings)
    redacted = {}
    app_settings["properties"].map { |name, value| redacted[name] = remove_passwords(value) }
    app_settings["properties"] = redacted
    app_settings
  end

  def redact_connection_strings(connection_strings)
    connection_strings["properties"].map do |name, object|
      object["value"] = remove_passwords(object["value"])
      object
    end
    connection_strings
  end

  def app_service_details(sub, app_service)
    app_service["service_plan"] = app_service_service_plan(app_service)
    app_service["app_connection_strings"] = redact_connection_strings(list_connection_strings(sub,
                                                                                              app_service["properties"]["resourceGroup"],
                                                                                              app_service["name"]))
    app_service["app_settings"] = redact_app_settings(list_app_settings(sub,
                                                                        app_service["properties"]["resourceGroup"],
                                                                        app_service["name"]))
    app_service
  end

  def summary_app(app)
    { name:               app["name"],
      resource_group:     app["properties"]["resourceGroup"],
      connection_strings: app["app_connection_strings"]["properties"].keys,
      app_settings:       app["app_settings"]["properties"].keys,
      service_plan_sku:   app["service_plan"]["sku"] }
  end

  def summary_db(db)
    sku = if db["sku"]
            db["sku"]
          elsif db["properties"]["sku"]
            db["properties"]["sku"]
          end
    { name: db["name"],
      sku:  sku }
  end

  def output_details(data)
    puts <<~OUTPUT
      ------------------------------------------

      #{JSON.pretty_generate(data)}

      ------------------------------------------

    OUTPUT
  end

  def database_types
    %w[database_managed_instances database_servers postgres_flexible_servers mysql_flexible_servers redis_databases]
  end

  def database_types_pretty
    database_types.map { |db| db.gsub!("_", " ").capitalize }.join(", ")
  end

  def list_and_output_all_databases(subscription)
    database_types.map do |type|
      databases = public_send("list_#{type}", subscription)
      databases_file_output(subscription, databases, type)
      databases["value"].map { |db| output_details(summary_db(db)) }
    end
  end

  def databases_file_output(subscription, databases, type)
    dir = File.join "subscription_#{subscription}", "databases"
    FileUtils.mkdir_p dir
    file_name = File.join dir, "#{type}.json"
    File.write(file_name, JSON.pretty_generate(databases))

    if databases["value"].empty?
      puts "No #{type} databases, API results written to #{file_name}"
      puts "\n"
    else
      puts "All #{type} databases written to #{file_name}"
    end
  end

  def app_service_file_output(subscription, app_service)
    dir = File.join "subscription_#{subscription}", "app_services"
    FileUtils.mkdir_p dir
    file_name = File.join dir, "#{app_service['name']}_#{app_service['properties']['resourceGroup']}.json"
    File.write(file_name, JSON.pretty_generate(app_service))
    puts "Entire App Service resource and Service Plan written to #{file_name}"
  end

  def get_details_and_output(subscription, app_service)
    details = app_service_details(subscription, app_service)
    app_service_file_output(subscription, details)
    output_details(summary_app(details))
  end

  def output_app_services_and_databases(subscription)
    all_app_services(subscription).map do |app_service|
      get_details_and_output(subscription, app_service)
    end
    list_and_output_all_databases(subscription)
  end

  def output_app_service(subscription, name)
    get_details_and_output(subscription, all_app_services(subscription)
                                         .select { |app_service| app_service["name"] == name }.first)
  end
end

class Cli
  include AzureAppServiceDetails

  def output_usage
    puts <<~USAGE
      Retrieve information from Azure for App Service's, their Service Plans
      and several types of Azure Databases including:
      #{database_types_pretty}

      Usage:

      First authenticate with Azure and set a token via the azure-cli using:

      az login
      az account set --subscription <SUBSCRIPTION_ID>
      export AZURE_TOKEN=$(az account get-access-token --query accessToken --output tsv)

      Retrieve all App Service's and Databases in a given subscription:
      #{$PROGRAM_NAME} <subscription-id>

      Retrieve a single App Service's:
      #{$PROGRAM_NAME} <subscription-id> <app-service-name>

      The output will include a summary to standard output as well as files written
      to the new directory in the current working directory in the format of:
      ./subscription_<subscription-id>/app_services/<app-service-name>_<app-service-resource-group-name>.json
      ./subscription_<subscription-id>/databases/<database-type>.json

      Required Azure API Access

      The following role includes all of the needed permissions to run this script:

      #{required_role_json}
    USAGE
  end

  def execute
    case ARGV.length
    when 1
      output_app_services_and_databases(ARGV[0])
    when 2
      output_app_service(ARGV[0], ARGV[1])
    else
      output_usage
    end
  end
end

Cli.new.execute
