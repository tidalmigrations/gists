#!/usr/bin/env ruby

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
  
  module AzureDBServer
    include HttpUtil
    include JSON
    
    def format_db_server_for_tidal(server)
      properties = server["properties"] || {}
      tags = (server["tags"] && server["tags"]["use"]) || server[:tags]&.split(": ")&.last
    
      STDERR.puts "Raw server data: #{server.inspect}"
      {
          host_name: server["name"] || server[:name],
          fqdn: properties["fullyQualifiedDomainName"],
          environment: tags,
          custom_fields: {
              location: server["location"]
          }
      }.compact
    end         
  end
  
  module AzureDB
    include HttpUtil
    include JSON

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
      # servers_data.each { |server| STDERR.puts "Detailed DB Server Data: #{server.inspect}" } 
      servers_data.each { |server| } 
      result = servers_data.map do |server|
        {
          name: server["name"],
          tags: server["tags"]&.map { |k, v| "#{k}: #{v}" }&.join(', '),
          detailed_data: server 
        }
      end      
      # STDERR.puts "DB Servers Result for #{resource_group}: #{result.inspect}"
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
        # STDERR.puts "Databases retrieved: #{result.inspect}"
        {
          name: db["name"],
          tags: db["tags"]&.map { |k, v| "#{k}: #{v}" }&.join(', '),
          max_size_bytes: db.dig("properties", "maxSizeBytes") || 0,
          location: db["location"]
        }
      end
      STDERR.puts "DBs for Server #{server_name} in #{resource_group}: #{result.inspect}"
      result
    end    
  end

class DBFetcher
  extend AzureDB
  extend AzureDBServer

  def self.sync_to_tidal_portal(data, type)
    file_path = "/tmp/tidal_#{type}_data.json"
    File.write(file_path, JSON.dump({ "#{type}": [data] }))

    # STDERR.puts "Data being sent to Tidal: #{JSON.dump({ "#{type}": [data] })}"

    command_output = `tidal request -X POST "/api/v1/#{type}/sync" #{file_path}`
    
    # STDERR.puts "Tidal Sync Output: #{command_output}"
  
    match = command_output.match(/"id":\s*(\d+)/)
    if match
      return match[1]
    else
      raise "Failed to capture ID from Tidal sync output."
    end
end

  

  def self.pull_from_azure_server_and_db
    all_servers = []
    all_dbs = []
  
    STDERR.puts "Fetching subscriptions..."
    subscriptions = list_subscriptions
  
    STDERR.puts "Found #{subscriptions.count} subscriptions."
    subscriptions.each do |subscription|
      STDERR.puts "Fetching resource groups for subscription #{subscription}..."
      resource_groups = list_resource_groups(subscription)
  
      STDERR.puts "Found #{resource_groups.count} resource groups in subscription #{subscription}."
      resource_groups.each do |resource_group|
        STDERR.puts "Fetching database servers in resource group #{resource_group}..."
        db_servers = list_db_servers(subscription, resource_group)

        db_servers.each do |server|
          detailed_server_data = server[:detailed_data]
          formatted_server = format_db_server_for_tidal(detailed_server_data)
          # STDERR.puts "Syncing server #{server["name"]} to Tidal..."
          server_id = sync_to_tidal_portal(formatted_server, "servers")

          # STDERR.puts "Server ID in Tidal: #{server_id}"

          begin
            dbs = list_databases_by_server(subscription, resource_group, server[:name])
            # STDERR.puts "Databases before adding to all_dbs: #{dbs.inspect}"
          rescue => e
            STDERR.puts "Error fetching databases for server #{server[:name]}: #{e.message}"
          end
          

          all_dbs.concat(dbs.map do |db|
            {
              server_name: server[:name], 
              database_name: db[:name],
              max_size_bytes: db[:max_size_bytes],
              tags: db[:tags],
              host_name: server_id,
              location: db[:location] 
            }
          end)
        end
      end
    end
  
    formatted_dbs = all_dbs.map do |db|
      # STDERR.puts "Transforming DB: #{db.inspect}"
      custom_fields = {}
      custom_fields[:az_resource] = "Azure SQL"
      custom_fields[:az_location] = db[:location]

      if db[:tags]
        tags = db[:tags].split(', ')
        # environment tags have a special place in Tidal
        env_tag = tags.find { |tag| tag.start_with?('environment: ') }
        environment = env_tag ? env_tag.split(': ')[1] : "production"

        # add all other tags as custom fields
        tags.each do |t|
          k = "az_lbl_#{ t.split(': ')[0] }"
          v = t.split(': ')[1] 
          custom_fields[k] = v unless k.start_with?('environment')
        end
      end

      db_object = {
        name: db[:database_name],
        database_engine: "SQL Server",
        database_size_mb: (db[:max_size_bytes] / (1024**2)).round,
        database_path: "N/A",
        description: "Azure SQL Database",
        server: { host_name: db[:server_name] },
      }
      db_object[:environment] = environment if environment
      db_object[:custom_fields] = custom_fields if custom_fields

      # STDERR.puts "## Transformed database: #{db_object.inspect}"
      db_object
    end

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
