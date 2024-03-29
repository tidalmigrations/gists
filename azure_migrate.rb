#!/usr/bin/env ruby

require 'net/http'
require 'json'

module HttpUtil
  def basic_request(path:, query_params: {}, headers: {})
    _, http = get_uri_http(
      path:         path,
      query_params: query_params
    )
    request = Object.const_get("Net::HTTP::Get").new(path)
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
      raise Error400, "Error accessing #{api_name} API: #{response.code}\n#{response.body}"

    else
      raise "Error accessing #{api_name} API: #{response.code}\n#{response.body}"
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
end

module AzureMigrate
  include HttpUtil
  include JSON

  def pull_from_azure_migrate
    if ENV["AZ_MIGRATE_SUBSCRIPTION"] == nil?
      raise "Error missing AZ_MIGRATE_SUBSCRIPTION environment variable."
    end
    if ENV["AZ_MIGRATE_RG"] == nil?
      raise "Error missing AZ_MIGRATE_RG environment variable."
    end
    if ENV["AZ_MIGRATE_PROJECT"] == nil?
      raise "Error missing AZ_MIGRATE_PROJECT environment variable."
    end

    subscription = ENV["AZ_MIGRATE_SUBSCRIPTION"]
    resource_group = ENV["AZ_MIGRATE_RG"]
    project = ENV["AZ_MIGRATE_PROJECT"]
    path = "/subscriptions/#{subscription}/"\
      "resourceGroups/#{resource_group}/providers/"\
      "Microsoft.Migrate/assessmentProjects/#{project}/"\
      "machines"

    version = "2020-05-01-preview"
    azure_api_request(
      method:       :get,
      path:         path,
      query_params: { "api-version": version },
      responses:    []
    )
  end

  def list_assessment_projects
    subscription = ENV["AZ_MIGRATE_SUBSCRIPTION"]
    resource_group = ENV["AZ_MIGRATE_RG"]
    version = "2020-05-01-preview"

    path = "https://management.azure.com/subscriptions/#{subscription}/resourceGroups/#{resource_group}/providers/\
Microsoft.Migrate/assessmentProjects?api-version=#{version}"
    assessments = basic_request(
      path:         path,
      query_params: { "api-version": version },
      headers:      {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    response = response_handler(api_name: "Azure Migrate", response: assessments)
    assessment_projects = []
    response["value"].each do |project|
      assessment_projects.push(project["name"])
    end
    puts "Listed assessment projects in in the follow subscription:\
resource group\n#{subscription}: #{resource_group} \n\n"
    pp assessment_projects
  end

  def parse_result(result)
    # TODO handle standard azure api errors and response
    if result
      gb_adder = 0
      properties = result["properties"]
      properties["disks"].each do |_, disk_value|
        gb_adder += disk_value['gigabytesAllocated']
      end
      ram_allocated_gb = (properties["megabytesOfMemory"] / 1000).to_i
      ip_addresses = []

      properties["networkAdapters"].each do |_, v|
        ip_addresses.push(*v["ipAddresses"])
      end
      response = {
        host_name:              properties["displayName"],
        ip_addresses:           ip_addresses.map{ |ip| { address: ip } },
        description:            properties["description"],
        custom_fields:          {
          arm_id: properties["discoveryMachineArmId"], operating_system_type: properties["operatingSystemType"],
          operating_system_name: properties["operatingSystemName"],
          operating_system_version: properties["operatingSystemVersion"],
          first_seen: properties["createdTimestamp"],
          last_seen: properties["updatedTimestamp"]
        },
        ram_allocated_gb:       ram_allocated_gb,
        storage_allocated_gb:   gb_adder.to_i,
        cpu_count:              properties["numberOfCores"],
        virtualization_cluster: properties["datacenterManagementServerName"],
      }
      response
    else
      puts "Experienced an error when trying to parse the result from the Azure Migrate API. If the error persists, \
contact us at support@tidalcloud.com"
      raise StandardError, "Error interacting with Azure API"
    end
  end

  private

    def azure_api_request(method:, path:, query_params: {}, responses: [])
      response = make_request(method:       method,
                              path:         "#{base_url}#{path}",
                              body:         nil,
                              query_params: query_params,
                              headers:      { "Authorization" => "Bearer #{get_token}" })

      first_response = response_handler(api_name: "Azure Migrate", response: response)
      next_link = first_response['nextLink']
      parsed_values = []
      first_response["value"].each do |server_value|
        parsed_values.push(parse_result(server_value))
      end
      responses.push(*parsed_values)

      while next_link != nil do
        path = "#{next_link}"
        next_response = basic_request(path:         path,
                                      query_params: query_params,
                                      headers:      { "Authorization" => "Bearer #{get_token}" })
        loop_response = response_handler(api_name: "Azure Migrate", response: next_response)
        parsed_paylod = []
        loop_response["value"].each do |payload_server_value|
          parsed_paylod.push(parse_result(payload_server_value))
        end
        responses.push(*parsed_paylod)
        next_link = loop_response['nextLink']
      end
      puts "#{({ servers: responses }).to_json}"
    end

    def base_url
      "https://management.azure.com"
    end

    def get_token
      ENV["AZURE_TOKEN"]
    end
end

class Migrate
  extend AzureMigrate

  case ARGV[0]
  when nil
    pull_from_azure_migrate
  when "-p"
    list_assessment_projects
  when "-h"
    puts <<~EOT
      Azure Migrate Assessment Project Server Export Menu:
       cmd | inputs        | description
           | -             | automatically start export
        -p | -             | list all assessment projects currently in the specified Azure Resource Group
        -h | -             | print help menu
    EOT
  else
    puts "Use the help flag -h to show the availale commands."
  end
end
