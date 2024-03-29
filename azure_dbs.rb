#!/usr/bin/env ruby
#
# This script will enumerate your Azure databases and sync the inventory to your
# tidal.cloud workspace.
#
# Usage: ./azure_dbs.rb | tidal sync dbs
#
# Prereq's:
#   1. az login - use the AZ CLI to login to azure, or run from Azure cloud shell
#   2. tidal login - use the Tidal CLI from get.tidal.sh to login to your tidal.cloud workspace
#

require 'net/http'
require 'json'

module HttpUtil
  def basic_request(path:, query_params: {}, headers: {})
    full_path = "#{base_url}#{path}"
    uri, http = get_uri_http(path: full_path, query_params: query_params)
    request = Net::HTTP::Get.new(uri.request_uri)
    headers.each { |k, v| request[k] = v }
    http.request(request)
  end

  def make_request(
    method:,
    path:,
    query_params: {},
    body: {},
    headers: {},
    form: [],
    ssl: true,
    timeout: 60,
    basic_auth: []
  )
    raise ArgumentError, "Must provide a valid method: #{valid_methods}" unless valid_methods.include? method.downcase

    uri, http = get_uri_http(path: "#{base_url}#{path}", ssl: ssl, query_params: query_params)
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

  def response_handler(api_name: "", response:, return_body: true, return_header: nil, return_response: false)
    if %w[200 202 204].include? response.code
      if return_header
        response[return_header]
      elsif return_response
        response
      elsif return_body
        if response.body.empty?
          true
        else
          JSON.parse response.body
        end
      end
    elsif response.code == "400"
      puts "API Name: #{api_name}"
      puts "Response Code: #{response.code}"
      puts "Response Body: #{response.body}"

      raise Error400, "Error accessing #{api_name} API (Code: #{response.code}). Response: #{response.body}"
    else
      raise "Error accessing #{api_name} API (Code: #{response.code}). Response: #{response.body}"
    end
  end

  class Error400 < StandardError
    def message
      "Either required headers are missing or the body of the JSON is malformed."
    end
  end

  def valid_methods
    [:get, :put, :post, :delete, :patch]
  end

  def get_uri_http(path:, query_params: nil, ssl: true)
    uri = URI(path)
    uri.query = URI.encode_www_form query_params if query_params
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = ssl
    [uri, http]
  end

  private

  def base_url
    "https://management.azure.com"
  end

  def get_token
    @@AZURE_TOKEN ||= ENV["AZURE_TOKEN"] || `az account get-access-token --query accessToken --output tsv`.strip
  end
end

module AzureHelper
  def extract_azure_tags_as_custom_fields(tags)
    custom_fields = {}
    if tags.is_a? String
      tags = tags.split(', ')
      tags.each do |t|
        k = "az_lbl_#{ t.split(': ')[0] }"
        v = t.split(': ')[1] 
        custom_fields[k] = v unless k.start_with?('environment')
      end
    elsif tags.is_a? Hash
      tags.each do |k, v|
        k = "az_lbl_#{ k }"
        custom_fields[k] = v unless k.start_with?('environment')
      end
    end
    custom_fields
  end

  def extract_environment_tag(tags)
    if tags.is_a? String
      env_tag = tags.split(', ').find { |tag| tag.start_with?('environment: ') }
      env_tag.split(': ')[1] if env_tag
    elsif tags.is_a? Hash
      tags['environment']
    end
  end
end

module AzureDBServer
  include HttpUtil
  include JSON

  def format_db_server_for_tidal(server)
    properties = server["properties"] || {}
    custom_fields = {}
    custom_fields[:az_resource] = server["type"]
    custom_fields[:az_location] = server["location"]
    custom_fields[:az_id] = server["id"]
    
    db_server = {}
    db_server[:host_name] = server["name"] || server[:name]
    fqdn = properties.fetch("fullyQualifiedDomainName", nil)
    db_server[:fqdn] = fqdn if fqdn
    db_server[:environment] = { name: extract_environment_tag(server["tags"]) } if server["tags"]
    custom_fields.merge!(extract_azure_tags_as_custom_fields(server["tags"])) if server["tags"]
    db_server[:custom_fields] = custom_fields
    db_server
  end


  def format_elastic_pool_for_tidal(pool)
    properties = pool["properties"] || {}
    custom_fields = {}
    custom_fields[:az_resource] = pool["type"]
    custom_fields[:az_location] = pool["location"]
    custom_fields[:az_id] = pool["id"]
    
    elastic_pool = {}
    elastic_pool[:host_name] = pool["name"] || pool[:name]
    fqdn = properties.fetch("fullyQualifiedDomainName", nil)
    elastic_pool[:fqdn] = fqdn if fqdn
    elastic_pool[:environment] = { name: extract_environment_tag(pool["tags"]) } if pool["tags"]
    custom_fields.merge!(extract_azure_tags_as_custom_fields(pool["tags"])) if pool["tags"]
    elastic_pool[:custom_fields] = custom_fields
    elastic_pool
  end
end

module AzureDB
  include HttpUtil
  include JSON

  # SQL API: https://learn.microsoft.com/en-us/rest/api/sql/
  DATABASE_API_VERSION = "2022-02-01-preview"

  def list_subscriptions
    path = "/subscriptions"
    version = "2023-07-01"
    response = basic_request(
      path:         path,
      query_params: { "api-version": version },
      headers:      {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    response_handler(api_name: "Azure Subscriptions", response: response)["value"].map { |sub| sub["subscriptionId"] }
  end

  def list_resource_groups(subscription)
    path = "/subscriptions/#{subscription}/resourcegroups"
    version = "2023-07-01"
    response = basic_request(
      path:         path,
      query_params: { "api-version": version },
      headers:      {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    response_handler(api_name: "Azure Resource Groups", response: response)["value"].map { |rg| rg["name"] }
  end

  def list_db_servers(subscription, resource_group)
    path = "/subscriptions/#{subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Sql/servers"
    response = basic_request(
      path:         path,
      query_params: { "api-version": DATABASE_API_VERSION },
      headers:      {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    servers_data = response_handler(api_name: "Azure Database Servers", response: response)["value"]
    servers_data.each { |server| } 
    result = servers_data.map do |server|
      {
        name: server["name"],
        tags: server["tags"]&.map { |k, v| "#{k}: #{v}" }&.join(', '),
        detailed_data: server 
      }
    end      
    result
  end


  def list_databases_by_server(subscription, resource_group, server_name)
    path = "/subscriptions/#{subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Sql/servers/#{server_name}/databases"
    response = basic_request(
      path:         path,
      query_params: { "api-version": DATABASE_API_VERSION },
      headers:      {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    result = response_handler(api_name: "Azure Databases By Server", response: response)["value"].map do |db|
      {
        name: db["name"],
        tags: db["tags"]&.map { |k, v| "#{k}: #{v}" }&.join(', '),
        max_size_bytes: db.dig("properties", "maxSizeBytes") || 0,
        location: db["location"],
        sku_name: db["sku"]["name"],
        sku_tier: db["sku"]["tier"],
        sku_capacity: db["sku"]["capacity"],
        type: db["type"],
        id: db["id"]
      }
    end
    result
  end    
end

module AzureElasticPool
  include HttpUtil
  include JSON

  DATABASE_API_VERSION = "2022-02-01-preview"

  def list_elastic_pools(subscription, resource_group, server_name)
    path = "/subscriptions/#{subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Sql/servers/#{server_name}/elasticPools"
    response = basic_request(
      path:         path,
      query_params: { "api-version": DATABASE_API_VERSION },
      headers:      {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    response_handler(api_name: "Azure Elastic Pools", response: response)["value"]
  end

  def list_databases_by_elastic_pool(subscription, resource_group, server_name, pool_name)
    path = "/subscriptions/#{subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Sql/servers/#{server_name}/elasticPools/#{pool_name}/databases"
    response = basic_request(
      path:         path,
      query_params: { "api-version": DATABASE_API_VERSION },
      headers:      {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    response_handler(api_name: "Azure Databases By Elastic Pool", response: response)["value"]
  end
end

class DBFetcher
  extend AzureDB
  extend AzureDBServer
  extend AzureHelper
  extend AzureElasticPool

  def self.sync_to_tidal_portal(data, type)
    file_path = "#{Dir.pwd}/tidal_#{type}_data-tmp.json"
    File.write(file_path, JSON.dump({ "#{type}": [data].flatten }))
    command_output = `tidal request -X POST "/api/v1/#{type}/sync" #{file_path}`
    match = command_output.match(/"id":\s*(\d+)/)
    if match
      return match[1]
    else
      # Emit the response for debugging purposes
      STDERR.puts "Error syncing to Tidal portal for type #{type}:"
      STDERR.puts command_output
  
      raise "Failed to capture ID from Tidal sync output. Command output: #{command_output}"
    end
  end

  # this method iterates across each subscription -> resource group -> DB Server
  # and then for each DB Server, it iterates across each database
  # and then for each database, it creates a Tidal DB and syncs it
  def self.pull_from_azure_server_and_db
    all_dbs = []

    STDERR.puts "Fetching subscriptions..."
    subscriptions = list_subscriptions

    STDERR.puts "=> Found #{subscriptions.count} subscriptions."
    subscriptions.each do |subscription|
      resource_groups = list_resource_groups(subscription)
      unless resource_groups.count == 0
        STDERR.puts "=> Found #{resource_groups.count} resource groups in subscription #{subscription}." 
      end

      resource_groups.each do |resource_group|
        db_servers = list_db_servers(subscription, resource_group)
        unless db_servers.count == 0
          STDERR.puts "=> Found #{db_servers.count} DB servers in resource group #{resource_group}" 
        end

          db_servers.each do |server|
            detailed_server_data = server[:detailed_data]
            formatted_server = format_db_server_for_tidal(detailed_server_data)
            server_id = sync_to_tidal_portal(formatted_server, "servers")
            STDERR.puts "+ Created server #{server_id} in Tidal Portal from #{formatted_server["host_name"]}."
          
            begin
              dbs = list_databases_by_server(subscription, resource_group, server[:name])
            rescue => e
              STDERR.puts "Error fetching databases for server #{server[:name]}: #{e.message}"
            end
          
            all_dbs.concat(dbs.map do |db|
              {
                server_name: server[:name], 
                server_id: server_id,
                database_name: db[:name],
                max_size_bytes: db[:max_size_bytes],
                tags: db[:tags],
                host_name: server_id,
                location: db[:location],
                type: db[:type],
                id: db[:id],
                sku_name: db[:sku_name],
                sku_tier: db[:sku_tier],
                sku_capacity: db[:sku_capacity]
              }
            end)

          # Fetch Elastic Pools
          elastic_pools = list_elastic_pools(subscription, resource_group, server[:name])
          elastic_pools.each do |pool|
            formatted_pool = format_elastic_pool_for_tidal(pool)
            pool_id = sync_to_tidal_portal(formatted_pool, "servers")
            STDERR.puts "+ Created Elastic Pool server #{pool_id} in Tidal Portal from #{formatted_pool["host_name"]}."
          
            # Fetch databases associated with the Elastic Pool
            dbs_by_pool = list_databases_by_elastic_pool(subscription, resource_group, server[:name], pool["name"])

            # Process each database for Elastic Pool
            all_dbs.concat(dbs_by_pool.map do |db|
              {
                server_name: pool["name"], 
                server_id: pool_id,
                database_name: db["name"],
                max_size_bytes: db["maxSizeBytes"],
                tags: db["tags"]&.map { |k, v| "#{k}: #{v}" }&.join(', '),
                host_name: pool_id,
                location: db["location"],
                type: db["type"],
                id: db["id"],
                sku_name: db["sku"]["name"],
                sku_tier: db["sku"]["tier"],
                sku_capacity: db["sku"]["capacity"]
              }
            end)
          end
        end
      end
    end

    formatted_dbs = all_dbs.map do |db|
      # STDERR.puts "Transforming DB: #{db.inspect}"
      custom_fields = {}
      custom_fields[:az_resource] = db[:type]
      custom_fields[:az_location] = db[:location]
      custom_fields[:az_id] = db[:id]
      custom_fields[:az_sku_name] = db[:sku_name]
      custom_fields[:az_sku_tier] = db[:sku_tier]
      custom_fields[:az_sku_capacity] = db[:sku_capacity]

      if db[:tags] && !db[:tags].empty?
        # environment tags have a special place in Tidal
        environment = extract_environment_tag( db[:tags] )

        # add all other tags as custom fields
        custom_fields.merge!( extract_azure_tags_as_custom_fields( db[:tags] ))
      end

      db_object = {}
      db_object[:name] = db[:database_name]
      db_object[:database_engine] = "SQL Server" 
      db_object[:database_size_mb] = ((db[:max_size_bytes] || 0) / (1024.0**2)).round
      db_object[:database_path] = "N/A"
      db_object[:description] = "Azure SQL Database"
      db_object[:server] = { host_name: db[:server_name] }
      db_object[:server_id] = db[:server_id]
      db_object[:environment] = { name: environment } if environment
      db_object[:custom_fields] = custom_fields

      # STDERR.puts "## Transformed database: #{db_object.inspect}"
      db_object
    end

    STDERR.puts "Syncing #{formatted_dbs.count} databases to Tidal Portal..."
    # It is necessary to sync with this method in order to get the DB -> Server relationship
    sync_to_tidal_portal( formatted_dbs, "database_instances" )
 
    # But it's also necessary to sync with `tidal sync dbs`
    # for the custom_fields to be created automatically.
    puts ({ database_instances: formatted_dbs }).to_json
  end

  case ARGV[0]
  when nil
    pull_from_azure_server_and_db
  when "-h"
    puts <<~EOT
      Azure Database Fetching Menu:
       cmd | inputs        | description
           | -             | fetch all Databases across servers
        -h | -             | print help menu
    EOT
  else
    puts "Use the help flag -h to show the available commands."
  end
end


