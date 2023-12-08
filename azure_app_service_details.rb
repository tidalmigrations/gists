#!/bin/env ruby

require "./azure_migrate.rb"
require "./azure_vms.rb"

module AzureAppServiceDetails
  include AzureMigrate
  include AzureAppService

  # to get resource groups
  include AzureVM

  def list_service_plans(subscription_id)
    azure_request "/subscriptions/#{subscription_id}/providers/Microsoft.Web/serverfarms"
  end

  def get_app_service(subscription, name, resource_group_name)
    azure_request "/subscriptions/#{subscription}/resourceGroups/#{resource_group_name}/providers/Microsoft.Web/sites/#{name}"
  end

  def app_settings(subscription, resource_group_name, app_name)
    azure_request "/subscriptions/#{subscription}/resourceGroups/#{resource_group_name}/providers/Microsoft.Web/sites/#{app_name}/config/appsettings/list"
  end

  # redundant, not needed
  def server_farms(subscription_id, group_name, app_service_plan_name)
    azure_request "/subscriptions/#{subscription_id}/resourceGroups/#{group_name}/providers/Microsoft.Web/serverfarms/#{app_service_plan_name}"
  end

  # empty as of now with current demo setup
  def worker_pools(sub)
    azure_request "/subscriptions/#{sub}/providers/Microsoft.Web/hostingEnvironments"
  end

  # can't query without worker_pool name value
  def private_endpoint_connections(sub, resource_group, name)
    azure_request "/subscriptions/#{sub}/resourceGroups/#{resource_group}/providers/Microsoft.Web/hostingEnvironments/#{name}/privateEndpointConnections"
  end

  def azure_request(path)
    JSON.parse(make_request(method:       :get,
                            path:         "#{base_url}#{path}",
                            body:         nil,
                            query_params: { "api-version": "2022-03-01" },
                            headers:      { "Authorization" => "Bearer #{get_token}" }).response.body)
  end

  def make_request(method:,path:,
    query_params: {},
    body: {},
    headers: {},
    form: [],
    ssl: true,
    timeout: 60,
    basic_auth: [])
    raise ArgumentError, "Must provide a valid method: #{valid_methods}" unless valid_methods.include? method.downcase

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

  def all_app_services(subscription)
    list_resource_groups(subscription).map do |resource_group|
      list_app_services(subscription, resource_group)
    end.flatten
  end

  def app_service_details(app_service)
    app_service["service_plan"] = azure_request app_service["properties"]["serverFarmId"]
    app_service
  end

  def output_details(app)
    site_config = app["properties"]["siteConfig"]
    puts <<~OUTPUT

      ------------------------------------------
      App Service
      #{app["name"]}

      Service Plan
      #{app["service_plan"]["name"]}

      Connection Strings
      #{site_config["connectionStrings"]}

      App Settings
      #{site_config["appSettings"]}

      Storage Accounts
      #{site_config["azureStorageAccounts"]}

      SKU
      #{app["service_plan"]["sku"]}
      ------------------------------------------

    OUTPUT
  end

  def app_service_file_output(app_service)
    file_name = "#{app_service["name"]}_#{app_service["properties"]["resourceGroup"]}.json"
    File.write(file_name, app_service.to_json)
    puts "Entire App Service resource and Service Plan written to #{file_name}"
  end

  # testing subscription
  '4c1a8af4-85cb-44c7-9528-491d3848d341'

  def output_all_app_services(subscription)
    all_app_services(subscription).map do | app_service |
      details = app_service_details(app_service)
      app_service_file_output(details)
      output_details(details)
    end
  end

  def output_app_service(subscription, name)
    selected = all_app_services(subscription).select { |app_service| app_service["name"] == name }.first
    details = app_service_details(selected)
    app_service_file_output(details)
    output_details(details)
  end

  def output_first_app_service(subscription)
    first = all_app_services(subscription).first
    details = app_service_details(first)
    app_service_file_output(details)
    output_details(details)
  end

  def output_usage
    puts <<~USAGE
      Retrieve information from Azure for App Service's and their Service Plans.

      Usage:

      Retrieve all App Service's in a given subscription:
      #{$0}  <subscription-id>


      Retrieve a single App Service's:
      #{$0}  <subscription-id> <app-service-name>


      The output will include a summary to Standard Output as well as a file written
      to the current working directory in the format of:
      <app-service-name>_<app-service-resource-group-name>.json

    USAGE
  end

  def cli_execute
    case ARGV.length
    when 1
      output_all_app_services ARGV[0]
    when 2
      output_app_service(ARGV[0], ARGV[1])
    else
      output_usage
    end
  end
end

include AzureAppServiceDetails
cli_execute
