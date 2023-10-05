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

  def get_disk_size(disk_id)
    response = basic_request(
      path: disk_id,
      query_params: { "api-version": "2023-04-02" }, 
      headers: {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    disk_data = response_handler(api_name: "Azure Disk", response: response)
    disk_data.dig("properties", "diskSizeGB") || 0
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
end


module AzureVM
  # Network API: https://learn.microsoft.com/en-us/rest/api/virtualnetwork/network-interfaces/get?tabs=HTTP
  NETWORK_API_VERSION = "2023-02-01"
  # Compute API: https://learn.microsoft.com/en-us/rest/api/compute/
  COMPUTE_API_VERSION = "2023-07-01"
  include HttpUtil
  include JSON


  # How to get the list of sizes from Azure API, 
  # curl -X GET \
  #  -H "Authorization: Bearer $AZURE_TOKEN" \
  #  "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Compute/locations/$LOCATION/vmSizes?api-version=$API_VERSION"

  VM_SIZE_MAPPING = {
    "Standard_M192ids_v2" => {'numberOfCores' => 192, 'memoryInMB' => 2097152},
  }

  def get_vm_size_data_from_api(subscription, location)
    path = "/subscriptions/#{subscription}/providers/Microsoft.Compute/locations/#{location}/vmSizes"

    response = basic_request(
      path: path,
      query_params: { "api-version": COMPUTE_API_VERSION },
      headers: {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    response_data = response_handler(api_name: "Azure VM Sizes", response: response)
    sizes = {}
    response_data["value"].each do |vm_size|
      sizes[vm_size["name"]] = {
        'numberOfCores' => vm_size["numberOfCores"],
        'memoryInMB' => vm_size["memoryInMB"]
      }
    end
    sizes
  end

  def get_vm_size_details(subscription, location, vm_size)
    if VM_SIZE_MAPPING[location] && VM_SIZE_MAPPING[location][vm_size]
      VM_SIZE_MAPPING[location][vm_size]
    else
      VM_SIZE_MAPPING[location] ||= get_vm_size_data_from_api(subscription, location)
      VM_SIZE_MAPPING[location][vm_size]
    end
  end

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

  def get_vms(subscription, resource_group)
    path = "/subscriptions/#{subscription}/resourceGroups/#{resource_group}/providers/Microsoft.Compute/virtualMachines"
    version = "2023-07-01"
    response = basic_request(
      path:         path,
      query_params: { "api-version": version },
      headers:      {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    vms = response_handler(api_name: "Azure Virtual Machines", response: response)["value"]

    # puts "Raw Azure VM Data: #{vms.inspect}"

    vms.map do |vm|
      private_ips = []
      public_ips = []
      fqdn_value = "N/A"
      vm["properties"]["networkProfile"]["networkInterfaces"].each do |nic|
        private_ip, public_ip, fqdn = get_vm_ip_addresses(subscription, nic["id"])
        private_ips += private_ip if private_ip
        public_ips += public_ip if public_ip
        fqdn_value = fqdn if fqdn && fqdn != "N/A" && fqdn_value == "N/A" 
      end

      # Print the FQDN to check if it's being retrieved correctly
      # puts "FQDN Value for VM #{vm['name']}: #{fqdn_value}"

      os_disk_id = vm.dig("properties", "storageProfile", "osDisk", "managedDisk", "id")
      os_disk_size = get_disk_size(os_disk_id)

      data_disk_size = vm.dig("properties", "storageProfile", "dataDisks").sum do |disk|
        disk_id = disk["managedDisk"]["id"]
        get_disk_size(disk_id)
      end

      total_storage_gb = os_disk_size + data_disk_size

      {
        host_name: vm["name"],
        location: vm["location"],
        ip_addresses: private_ips.concat(public_ips).map{|ip| {address: ip}},
        fqdn: fqdn_value,
        assigned_id: vm["id"],
        # ram_allocated_gb: vm.dig("properties", "hardwareProfile", "vmSize"), 
        # cpu_count: vm.dig("properties", "hardwareProfile", "vmSize"), 
        vm_size: vm.dig("properties", "hardwareProfile", "vmSize"),
        storage_allocated_gb: total_storage_gb || "N/A",
        operating_system: vm.dig("properties", "storageProfile", "osDisk", "osType"),
        operating_system_version: vm.dig("properties", "storageProfile", "imageReference", "version"),
        environment: vm["tags"] && vm["tags"]["Environment"],
        zone: vm.dig("properties", "availabilitySet", "id")
      }
    end
  end

  def get_vm_ip_addresses(subscription, nic_uri)
    response = basic_request(
      path: nic_uri,
      query_params: { "api-version": NETWORK_API_VERSION },
      headers: {
        "Authorization" => "Bearer #{get_token}"
      }
    )
    response_parsed = response_handler(api_name: "Azure Network Interfaces", response: response)

    ip_configs = response_parsed['properties']['ipConfigurations']

    private_ips = []
    public_ips = []
    chosen_fqdn = nil

    ip_configs.each do |ip_config|
      private_ips.push(ip_config['properties']['privateIPAddress']) if ip_config['properties']['privateIPAddress']

      if ip_config['properties']['publicIPAddress'] && ip_config['properties']['publicIPAddress']['id']
        public_ip_response = basic_request(
          path: ip_config['properties']['publicIPAddress']['id'],
          query_params: { "api-version": NETWORK_API_VERSION },
          headers: {
            "Authorization" => "Bearer #{get_token}"
          }
        )
        public_ip_parsed = response_handler(api_name: "Azure Public IP", response: public_ip_response)

        # STDERR.puts "Public IP Details for NIC URI #{nic_uri}: #{public_ip_parsed.inspect}"

        public_ips.push(public_ip_parsed['properties']['ipAddress']) if public_ip_parsed['properties']['ipAddress']

        fqdn = public_ip_parsed.dig("properties", "dnsSettings", "fqdn")
        if fqdn && chosen_fqdn.nil?
          chosen_fqdn = fqdn
          # STDERR.puts "Retrieved FQDN for NIC URI #{nic_uri}: #{chosen_fqdn}"
        end
      else
        STDERR.puts "No public IP details found for NIC with URI: #{nic_uri}"
      end
    end

    chosen_fqdn ||= 'N/A'

    [private_ips, public_ips, chosen_fqdn]

  end

  def pull_from_azure_vm
    all_vms = []

    STDERR.puts "Fetching subscriptions..."
    subscriptions = list_subscriptions

    STDERR.puts "Found #{subscriptions.count} subscriptions."
    subscriptions.each do |subscription|
      STDERR.puts "Fetching resource groups for subscription #{subscription}..."
      resource_groups = list_resource_groups(subscription)

      STDERR.puts "Found #{resource_groups.count} resource groups in subscription #{subscription}."
      resource_groups.each do |resource_group|
        STDERR.puts "Fetching VMs in resource group #{resource_group}..."
        vms = get_vms(subscription, resource_group)

        vms.map! do |vm|
          size_details = get_vm_size_details(subscription, vm[:location], vm[:vm_size]) || {}

          {
            host_name: vm[:host_name],
            ip_addresses: vm[:ip_addresses].is_a?(Array) ? vm[:ip_addresses].flatten.map{|addr| {address: addr}} : [{address: vm[:ip_addresses]}],
            description: "Azure VM", 
            operating_system: vm[:operating_system] || "N/A",
            operating_system_version: vm[:operating_system_version] || "N/A",
            custom_fields: {
              location: vm[:location],
              operating_system_name: vm[:operating_system] || "N/A"
            },
            ram_allocated_gb: size_details['memoryInMB'] ? (size_details['memoryInMB'] / 1024).to_i : nil,
            cpu_count: size_details['numberOfCores'] || "N/A",
            storage_allocated_gb: vm[:storage_allocated_gb] || "N/A",
            fqdn: vm[:fqdn].nil? || vm[:fqdn].empty? ? "N/A" : vm[:fqdn],
          }
        end

        all_vms.concat(vms)
      end
    end

    puts ({ servers: all_vms }).to_json
  end

  private
  def base_url
    "https://management.azure.com"
  end
  def get_token
    @@AZURE_TOKEN ||= ENV["AZURE_TOKEN"] || `az account get-access-token --query accessToken --output tsv`.strip
  end
end

class VMFetcher
  extend AzureVM

  case ARGV[0]
  when nil
    pull_from_azure_vm
  when "-h"
    puts <<~EOT
        Azure VM Fetching Menu:
         cmd | inputs        | description
             | -             | fetch all VMs across subscriptions and resource groups
          -h | -             | print help menu
    EOT
  else
    puts "Use the help flag -h to show the available commands."
  end
end
