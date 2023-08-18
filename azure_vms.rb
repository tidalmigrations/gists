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
  end
  

  module AzureVM
    NETWORK_API_VERSION = "2021-05-01"
    include HttpUtil
    include JSON
  
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
  
      vms.map do |vm|
        STDERR.puts "Processing VM: #{vm['name']}"
        private_ips = []
        public_ips = []
        vm["properties"]["networkProfile"]["networkInterfaces"].each do |nic|
            private_ip, public_ip = get_vm_ip_addresses(subscription, nic["id"])
            private_ips += private_ip
            public_ips += public_ip
        end
  
        {
            host_name: vm["name"],
            location: vm["location"],
            ip_addresses: [private_ips, public_ips],
            fqdn: vm.dig("properties", "dnsSettings", "fqdn"),
            assigned_id: vm["id"],
            ram_allocated_gb: vm.dig("properties", "hardwareProfile", "vmSize"), 
            cpu_count: vm.dig("properties", "hardwareProfile", "vmSize"), 
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
                public_ips.push(public_ip_parsed['properties']['ipAddress']) if public_ip_parsed['properties']['ipAddress']
            end
        end
      
        [private_ips, public_ips]
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
          all_vms.concat(vms)
        end
      end
    
      STDERR.puts "Total VMs found: #{all_vms.count}"

      # puts "Sample VM: #{all_vms.first}"
      # puts "Raw VM Structure: #{all_vms.first.inspect}"


      formatted_vms = all_vms.map do |vm|
        {
            ip_addresses: vm[:ip_addresses][0] + vm[:ip_addresses][1], 
            description: "Azure VM", 
            host_name: vm[:host_name] || "N/A",
            fqdn: vm[:fqdn] || "N/A",
            # assigned_id: vm[:assigned_id] || "N/A",
            # ram_allocated_gb: vm[:ram_allocated_gb] || "N/A", 
            # cpu_count: vm[:cpu_count] || "N/A", 
            operating_system_name: vm[:operating_system] || "N/A",
            operating_system_version: vm[:operating_system_version] || "N/A",
            # environment: vm[:environment] || "N/A",
            zone: vm[:zone] || "N/A",
            location: vm[:location],
            # ip_addresses: vm[:ip_addresses].flatten
        }

        # {
        #   host_name: vm[:host_name],
        #   ip_addresses: vm[:ip_addresses][0] + vm[:ip_addresses][1], 
        #   description: "Azure VM", 
        #   custom_fields: {
        #     location: vm[:location]
        #   },
          # Add more fields
        # }
    end
    
      
      puts ({ servers: formatted_vms }).to_json
      
    end
      
    private
  
      def base_url
        "https://management.azure.com"
      end
  
      def get_token
        ENV["AZURE_TOKEN"]
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
