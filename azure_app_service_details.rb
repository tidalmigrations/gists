require "./azure_migrate.rb"
require "./azure_vms.rb"

module AzureAppServiceDetails
  include AzureMigrate
  include AzureAppService

  def list_service_plans(subscription_id)
    azure_request "/subscriptions/#{subscription_id}/providers/Microsoft.Web/serverfarms"
  end

  def get_app_service(name, resource_group_name)
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

  def subscription
    '4c1a8af4-85cb-44c7-9528-491d3848d341'
  end

  def resource_group
    "app-service-demo"
  end

  def all_app_services
    list_app_services(subscription, resource_group)
  end

  def first_name_and_resource_group
    all = all_app_services
    [all.first["name"], all.first["properties"]["resourceGroup"]]
  end

  def app_service_details(app_service_name, resource_group_name)
    app = get_app_service(app_service_name, resource_group_name)
    service_plan = azure_request app["properties"]["serverFarmId"]
    [app, service_plan]
  end

  def output_details(app, service_plan)
    site_config = app["properties"]["siteConfig"]
    pp "APP SERVICE RESOURCE ---#{app["name"]}------"
    pp app
    pp "SERVICE PLAN ---------------------------"
    pp service_plan
    puts "\n\n"
    pp "CONNECTION STRINGS ---------------------"
    pp site_config["connectionStrings"]
    pp "APP Settings ---------------------------"
    pp site_config["appSettings"]
    pp "STORAGE ACCOUNTS -----------------------"
    pp site_config["azureStorageAccounts"]
    pp "SKU ----------------------------------- "
    pp service_plan["sku"]
  end

  def first_details
    name, resource_group = first_name_and_resource_group
    details = app_service_details(name, resource_group)
    File.write("#{name}_#{resource_group}.json", details.to_json)
    output_details(*details)
  end
end
