#!/bin/env ruby
module AzureAppServiceApi
  require "net/http"

  def list_resource_groups(subscription)
    azure_request("#{base_sub(subscription)}/resourcegroups", :get, "2023-07-01")["value"]
  end

  def list_app_services(subscription, resource_group)
    azure_site(subscription, resource_group, "/", :get, "2022-09-01")["value"]
  end

  def list_service_plans(subscription, resource_group)
    azure_rg(subscription, resource_group, "/serverfarms")
  end

  def get_app_service(subscription, name, resource_group)
    azure_site(subscription, resource_group, "/#{name}")
  end

  def connection_strings(subscription, resource_group, app_name)
    azure_site(subscription, resource_group, "#{app_name}/config/connectionstrings/list", :post)
  end

  # currently not returning needed Appsettings values
  def list_app_configs(subscription, resource_group, app_name)
    azure_site(subscription, resource_group, "/#{app_name}/config/web")
    # returns similar result but appSettings empty as well
    # azure_request "/subscriptions/#{subscription}/resourceGroups/#{resource_group_name}/providers/" \
    #               "Microsoft.Web/sites/#{app_name}/config"
  end

  # currently not returning needed Appsettings values
  def app_settings(subscription, resource_group, app_name)
    azure_site(subscription, resource_group, "/#{app_name}/config/appsettings/list")
  end

  # redundant, not needed, URL for this resource returned with app service object
  # also note, 'server farm' is analogous for 'service plan'
  def server_farms(subscription, resource_group, app_service_plan_name)
    azure_rg subscription, resource_group, "serverfarms/#{app_service_plan_name}"
  end

  def app_service_service_plan(app_service)
    azure_request app_service["properties"]["serverFarmId"]
  end

  # empty as of now with current demo setup
  def worker_pools(sub)
    azure_request "#{base_sub(sub)}/providers/Microsoft.Web/hostingEnvironments"
  end

  # can only query with a worker_pool name value
  def private_endpoint_connections(subscription, resource_group, name)
    azure_rg subscription, resource_group, "/hostingEnvironments/#{name}/privateEndpointConnections"
  end

  def azure_rg(subscription, resource_group, path)
    azure_request "#{base_rg(subscription, resource_group)}/#{path}"
  end

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

  def all_app_services(subscription)
    list_resource_groups(subscription).map do |resource_group|
      list_app_services(subscription, resource_group["name"])
    end.flatten
  end

  def app_service_details(sub, app_service)
    app_service["service_plan"] = app_service_service_plan(app_service)
    app_service["app_connection_strings"] = connection_strings(sub, app_service["properties"]["resourceGroup"],
                                                               app_service["name"])
    app_service["app_configs"] = list_app_configs(sub, app_service["properties"]["resourceGroup"], app_service["name"])
    app_service
  end

  def summary_app(app)
    site_config = app["properties"]["siteConfig"]
    { name:               app["name"],
      resource_group:     app["properties"]["resourceGroup"],
      connection_strings: app["app_connection_strings"]["properties"].keys,
      app_settings:       [site_config["appSettings"],
                           app["properties"]["siteProperties"]["appSettings"]],
      storage_accounts:   site_config["azureStorageAccounts"],
      service_plan_sku:   app["service_plan"]["sku"] }
  end

  def output_details(app)
    puts <<~OUTPUT

      #{JSON.pretty_generate(summary_app(app))}

      ------------------------------------------

    OUTPUT
  end

  def app_service_file_output(subscription, app_service)
    dir = "subscription_#{subscription}_app_services"
    FileUtils.mkdir_p dir
    file_name = File.join dir, "#{app_service['name']}_#{app_service['properties']['resourceGroup']}.json"
    File.write(file_name, app_service.to_json)
    puts "Entire App Service resource and Service Plan written to #{file_name}"
  end

  def get_details_and_output(subscription, app_service)
    details = app_service_details(subscription, app_service)
    app_service_file_output(subscription, details)
    output_details(details)
  end

  def output_all_app_services(subscription)
    all_app_services(subscription).map do |app_service|
      get_details_and_output(subscription, app_service)
    end
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
      Retrieve information from Azure for App Service's and their Service Plans.

      Usage:

      First authenticate with Azure and set a token via the azure-cli using:

      az login
      az account set --subscription <SUBSCRIPTION_ID>
      export AZURE_TOKEN=$(az account get-access-token --query accessToken --output tsv)

      Retrieve all App Service's in a given subscription:
      #{$PROGRAM_NAME} <subscription-id>

      Retrieve a single App Service's:
      #{$PROGRAM_NAME} <subscription-id> <app-service-name>

      The output will include a summary to standard output as well as a file written
      to the new directory in the current working directory in the format of:
      ./subscription_<subscription-id>_app_services/<app-service-name>_<app-service-resource-group-name>.json
    USAGE
  end

  def execute
    case ARGV.length
    when 1
      output_all_app_services(ARGV[0])
    when 2
      output_app_service(ARGV[0], ARGV[1])
    else
      output_usage
    end
  end
end

Cli.new.execute
