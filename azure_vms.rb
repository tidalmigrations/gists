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
        query_params: { "api-version": "2023-04-02" }, # This API version might need to be adjusted
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
    NETWORK_API_VERSION = "2021-05-01"
    include HttpUtil
    include JSON

    VM_SIZE_MAPPING = {
      "Standard_B1ls" => {'numberOfCores' => 1, 'memoryInMB' => 512},
      "Standard_B1ms" => {'numberOfCores' => 1, 'memoryInMB' => 2048},
      "Standard_B1s" => {'numberOfCores' => 1, 'memoryInMB' => 1024},
      "Standard_B2ms" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_B2s" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_B4ms" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_B8ms" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_B12ms" => {'numberOfCores' => 12, 'memoryInMB' => 49152},
      "Standard_B16ms" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_B20ms" => {'numberOfCores' => 20, 'memoryInMB' => 81920},
      "Standard_D1_v2" => {'numberOfCores' => 1, 'memoryInMB' => 3584},
      "Standard_D2_v2" => {'numberOfCores' => 2, 'memoryInMB' => 7168},
      "Standard_D3_v2" => {'numberOfCores' => 4, 'memoryInMB' => 14336},
      "Standard_D4_v2" => {'numberOfCores' => 8, 'memoryInMB' => 28672},
      "Standard_D5_v2" => {'numberOfCores' => 16, 'memoryInMB' => 57344},
      "Standard_D11_v2" => {'numberOfCores' => 2, 'memoryInMB' => 14336},
      "Standard_D12_v2" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_D13_v2" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Standard_D14_v2" => {'numberOfCores' => 16, 'memoryInMB' => 114688},
      "Standard_D15_v2" => {'numberOfCores' => 20, 'memoryInMB' => 143360},
      "Standard_D2_v2_Promo" => {'numberOfCores' => 2, 'memoryInMB' => 7168},
      "Standard_D3_v2_Promo" => {'numberOfCores' => 4, 'memoryInMB' => 14336},
      "Standard_D4_v2_Promo" => {'numberOfCores' => 8, 'memoryInMB' => 28672},
      "Standard_D5_v2_Promo" => {'numberOfCores' => 16, 'memoryInMB' => 57344},
      "Standard_D11_v2_Promo" => {'numberOfCores' => 2, 'memoryInMB' => 14336},
      "Standard_D12_v2_Promo" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_D13_v2_Promo" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Standard_D14_v2_Promo" => {'numberOfCores' => 16, 'memoryInMB' => 114688},
      "Standard_F1" => {'numberOfCores' => 1, 'memoryInMB' => 2048},
      "Standard_F2" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_F4" => {'numberOfCores' => 4, 'memoryInMB' => 8192},
      "Standard_F8" => {'numberOfCores' => 8, 'memoryInMB' => 16384},
      "Standard_F16" => {'numberOfCores' => 16, 'memoryInMB' => 32768},
      "Standard_DS1_v2" => {'numberOfCores' => 1, 'memoryInMB' => 3584},
      "Standard_DS2_v2" => {'numberOfCores' => 2, 'memoryInMB' => 7168},
      "Standard_DS3_v2" => {'numberOfCores' => 4, 'memoryInMB' => 14336},
      "Standard_DS4_v2" => {'numberOfCores' => 8, 'memoryInMB' => 28672},
      "Standard_DS5_v2" => {'numberOfCores' => 16, 'memoryInMB' => 57344},
      "Standard_DS11-1_v2" => {'numberOfCores' => 2, 'memoryInMB' => 14336},
      "Standard_DS11_v2" => {'numberOfCores' => 2, 'memoryInMB' => 14336},
      "Standard_DS12-1_v2" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_DS12-2_v2" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_DS12_v2" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_DS13-2_v2" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Standard_DS13-4_v2" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Standard_DS13_v2" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Standard_DS14-4_v2" => {'numberOfCores' => 16, 'memoryInMB' => 114688},
      "Standard_DS14-8_v2" => {'numberOfCores' => 16, 'memoryInMB' => 114688},
      "Standard_DS14_v2" => {'numberOfCores' => 16, 'memoryInMB' => 114688},
      "Standard_DS15_v2" => {'numberOfCores' => 20, 'memoryInMB' => 143360},
      "Standard_DS2_v2_Promo" => {'numberOfCores' => 2, 'memoryInMB' => 7168},
      "Standard_DS3_v2_Promo" => {'numberOfCores' => 4, 'memoryInMB' => 14336},
      "Standard_DS4_v2_Promo" => {'numberOfCores' => 8, 'memoryInMB' => 28672},
      "Standard_DS5_v2_Promo" => {'numberOfCores' => 16, 'memoryInMB' => 57344},
      "Standard_DS11_v2_Promo" => {'numberOfCores' => 2, 'memoryInMB' => 14336},
      "Standard_DS12_v2_Promo" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_DS13_v2_Promo" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Standard_DS14_v2_Promo" => {'numberOfCores' => 16, 'memoryInMB' => 114688},
      "Standard_F1s" => {'numberOfCores' => 1, 'memoryInMB' => 2048},
      "Standard_F2s" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_F4s" => {'numberOfCores' => 4, 'memoryInMB' => 8192},
      "Standard_F8s" => {'numberOfCores' => 8, 'memoryInMB' => 16384},
      "Standard_F16s" => {'numberOfCores' => 16, 'memoryInMB' => 32768},
      "Standard_A1_v2" => {'numberOfCores' => 1, 'memoryInMB' => 2048},
      "Standard_A2m_v2" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_A2_v2" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_A4m_v2" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_A4_v2" => {'numberOfCores' => 4, 'memoryInMB' => 8192},
      "Standard_A8m_v2" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_A8_v2" => {'numberOfCores' => 8, 'memoryInMB' => 16384},
      "Standard_D2_v3" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4_v3" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8_v3" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16_v3" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32_v3" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48_v3" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64_v3" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D2s_v3" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4s_v3" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8s_v3" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16s_v3" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32s_v3" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48s_v3" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64s_v3" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_E2_v3" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4_v3" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8_v3" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16_v3" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20_v3" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32_v3" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48_v3" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64i_v3" => {'numberOfCores' => 64, 'memoryInMB' => 442368},
      "Standard_E64_v3" => {'numberOfCores' => 64, 'memoryInMB' => 442368},
      "Standard_E2s_v3" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4-2s_v3" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E4s_v3" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8-2s_v3" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8-4s_v3" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8s_v3" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16-4s_v3" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16-8s_v3" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16s_v3" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20s_v3" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32-8s_v3" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32-16s_v3" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32s_v3" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48s_v3" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64-16s_v3" => {'numberOfCores' => 64, 'memoryInMB' => 442368},
      "Standard_E64-32s_v3" => {'numberOfCores' => 64, 'memoryInMB' => 442368},
      "Standard_E64is_v3" => {'numberOfCores' => 64, 'memoryInMB' => 442368},
      "Standard_E64s_v3" => {'numberOfCores' => 64, 'memoryInMB' => 442368},
      "Standard_D2ds_v4" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4ds_v4" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8ds_v4" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16ds_v4" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32ds_v4" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48ds_v4" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64ds_v4" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D2ds_v5" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4ds_v5" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8ds_v5" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16ds_v5" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32ds_v5" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48ds_v5" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64ds_v5" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D96ds_v5" => {'numberOfCores' => 96, 'memoryInMB' => 393216},
      "Standard_D2d_v4" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4d_v4" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8d_v4" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16d_v4" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32d_v4" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48d_v4" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64d_v4" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D2d_v5" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4d_v5" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8d_v5" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16d_v5" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32d_v5" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48d_v5" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64d_v5" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D96d_v5" => {'numberOfCores' => 96, 'memoryInMB' => 393216},
      "Standard_D2s_v4" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4s_v4" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8s_v4" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16s_v4" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32s_v4" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48s_v4" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64s_v4" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D2s_v5" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4s_v5" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8s_v5" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16s_v5" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32s_v5" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48s_v5" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64s_v5" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D96s_v5" => {'numberOfCores' => 96, 'memoryInMB' => 393216},
      "Standard_D2_v4" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4_v4" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8_v4" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16_v4" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32_v4" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48_v4" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64_v4" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D2_v5" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4_v5" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8_v5" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16_v5" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32_v5" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48_v5" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64_v5" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D96_v5" => {'numberOfCores' => 96, 'memoryInMB' => 393216},
      "Standard_E2ds_v4" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4-2ds_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E4ds_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8-2ds_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8-4ds_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8ds_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16-4ds_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16-8ds_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16ds_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20ds_v4" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32-8ds_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32-16ds_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32ds_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48ds_v4" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64-16ds_v4" => {'numberOfCores' => 64, 'memoryInMB' => 516096},
      "Standard_E64-32ds_v4" => {'numberOfCores' => 64, 'memoryInMB' => 516096},
      "Standard_E64ds_v4" => {'numberOfCores' => 64, 'memoryInMB' => 516096},
      "Standard_E2ds_v5" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4-2ds_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E4ds_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8-2ds_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8-4ds_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8ds_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16-4ds_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16-8ds_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16ds_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20ds_v5" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32-8ds_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32-16ds_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32ds_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48ds_v5" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64-16ds_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64-32ds_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64ds_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96-24ds_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96-48ds_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96ds_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E104ids_v5" => {'numberOfCores' => 104, 'memoryInMB' => 688128},
      "Standard_E2d_v4" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4d_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8d_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16d_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20d_v4" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32d_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48d_v4" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64d_v4" => {'numberOfCores' => 64, 'memoryInMB' => 516096},
      "Standard_E2d_v5" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4d_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8d_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16d_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20d_v5" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32d_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48d_v5" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64d_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96d_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E104id_v5" => {'numberOfCores' => 104, 'memoryInMB' => 688128},
      "Standard_E2s_v4" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4-2s_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E4s_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8-2s_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8-4s_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8s_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16-4s_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16-8s_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16s_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20s_v4" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32-8s_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32-16s_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32s_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48s_v4" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64-16s_v4" => {'numberOfCores' => 64, 'memoryInMB' => 516096},
      "Standard_E64-32s_v4" => {'numberOfCores' => 64, 'memoryInMB' => 516096},
      "Standard_E64s_v4" => {'numberOfCores' => 64, 'memoryInMB' => 516096},
      "Standard_E2s_v5" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4-2s_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E4s_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8-2s_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8-4s_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8s_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16-4s_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16-8s_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16s_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20s_v5" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32-8s_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32-16s_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32s_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48s_v5" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64-16s_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64-32s_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64s_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96-24s_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96-48s_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96s_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E104is_v5" => {'numberOfCores' => 104, 'memoryInMB' => 688128},
      "Standard_E2_v4" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20_v4" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48_v4" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64_v4" => {'numberOfCores' => 64, 'memoryInMB' => 516096},
      "Standard_E2_v5" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20_v5" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48_v5" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E104i_v5" => {'numberOfCores' => 104, 'memoryInMB' => 688128},
      "Standard_F2s_v2" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_F4s_v2" => {'numberOfCores' => 4, 'memoryInMB' => 8192},
      "Standard_F8s_v2" => {'numberOfCores' => 8, 'memoryInMB' => 16384},
      "Standard_F16s_v2" => {'numberOfCores' => 16, 'memoryInMB' => 32768},
      "Standard_F32s_v2" => {'numberOfCores' => 32, 'memoryInMB' => 65536},
      "Standard_F48s_v2" => {'numberOfCores' => 48, 'memoryInMB' => 98304},
      "Standard_F64s_v2" => {'numberOfCores' => 64, 'memoryInMB' => 131072},
      "Standard_F72s_v2" => {'numberOfCores' => 72, 'memoryInMB' => 147456},
      "Standard_E2bs_v5" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4bs_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8bs_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16bs_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E32bs_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48bs_v5" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64bs_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96bs_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E112ibs_v5" => {'numberOfCores' => 112, 'memoryInMB' => 688128},
      "Standard_E2bds_v5" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4bds_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8bds_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16bds_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E32bds_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48bds_v5" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64bds_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96bds_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E112ibds_v5" => {'numberOfCores' => 112, 'memoryInMB' => 688128},
      "Standard_D2ls_v5" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_D4ls_v5" => {'numberOfCores' => 4, 'memoryInMB' => 8192},
      "Standard_D8ls_v5" => {'numberOfCores' => 8, 'memoryInMB' => 16384},
      "Standard_D16ls_v5" => {'numberOfCores' => 16, 'memoryInMB' => 32768},
      "Standard_D32ls_v5" => {'numberOfCores' => 32, 'memoryInMB' => 65536},
      "Standard_D48ls_v5" => {'numberOfCores' => 48, 'memoryInMB' => 98304},
      "Standard_D64ls_v5" => {'numberOfCores' => 64, 'memoryInMB' => 131072},
      "Standard_D96ls_v5" => {'numberOfCores' => 96, 'memoryInMB' => 196608},
      "Standard_D2lds_v5" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_D4lds_v5" => {'numberOfCores' => 4, 'memoryInMB' => 8192},
      "Standard_D8lds_v5" => {'numberOfCores' => 8, 'memoryInMB' => 16384},
      "Standard_D16lds_v5" => {'numberOfCores' => 16, 'memoryInMB' => 32768},
      "Standard_D32lds_v5" => {'numberOfCores' => 32, 'memoryInMB' => 65536},
      "Standard_D48lds_v5" => {'numberOfCores' => 48, 'memoryInMB' => 98304},
      "Standard_D64lds_v5" => {'numberOfCores' => 64, 'memoryInMB' => 131072},
      "Standard_D96lds_v5" => {'numberOfCores' => 96, 'memoryInMB' => 196608},
      "Standard_B2ls_v2" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_B2s_v2" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_B2ts_v2" => {'numberOfCores' => 2, 'memoryInMB' => 1024},
      "Standard_B4ls_v2" => {'numberOfCores' => 4, 'memoryInMB' => 8192},
      "Standard_B4s_v2" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_B8ls_v2" => {'numberOfCores' => 8, 'memoryInMB' => 16384},
      "Standard_B8s_v2" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_B16ls_v2" => {'numberOfCores' => 16, 'memoryInMB' => 32768},
      "Standard_B16s_v2" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_B32ls_v2" => {'numberOfCores' => 32, 'memoryInMB' => 65536},
      "Standard_B32s_v2" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_M64" => {'numberOfCores' => 64, 'memoryInMB' => 1024000},
      "Standard_M64m" => {'numberOfCores' => 64, 'memoryInMB' => 1792000},
      "Standard_M128" => {'numberOfCores' => 128, 'memoryInMB' => 2048000},
      "Standard_M128m" => {'numberOfCores' => 128, 'memoryInMB' => 3891200},
      "Standard_M8-2ms" => {'numberOfCores' => 8, 'memoryInMB' => 224000},
      "Standard_M8-4ms" => {'numberOfCores' => 8, 'memoryInMB' => 224000},
      "Standard_M8ms" => {'numberOfCores' => 8, 'memoryInMB' => 224000},
      "Standard_M16-4ms" => {'numberOfCores' => 16, 'memoryInMB' => 448000},
      "Standard_M16-8ms" => {'numberOfCores' => 16, 'memoryInMB' => 448000},
      "Standard_M16ms" => {'numberOfCores' => 16, 'memoryInMB' => 448000},
      "Standard_M32-8ms" => {'numberOfCores' => 32, 'memoryInMB' => 896000},
      "Standard_M32-16ms" => {'numberOfCores' => 32, 'memoryInMB' => 896000},
      "Standard_M32ls" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_M32ms" => {'numberOfCores' => 32, 'memoryInMB' => 896000},
      "Standard_M32ts" => {'numberOfCores' => 32, 'memoryInMB' => 196608},
      "Standard_M64-16ms" => {'numberOfCores' => 64, 'memoryInMB' => 1792000},
      "Standard_M64-32ms" => {'numberOfCores' => 64, 'memoryInMB' => 1792000},
      "Standard_M64ls" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_M64ms" => {'numberOfCores' => 64, 'memoryInMB' => 1792000},
      "Standard_M64s" => {'numberOfCores' => 64, 'memoryInMB' => 1048576},
      "Standard_M128-32ms" => {'numberOfCores' => 128, 'memoryInMB' => 3891200},
      "Standard_M128-64ms" => {'numberOfCores' => 128, 'memoryInMB' => 3891200},
      "Standard_M128ms" => {'numberOfCores' => 128, 'memoryInMB' => 3891200},
      "Standard_M128s" => {'numberOfCores' => 128, 'memoryInMB' => 2048000},
      "Standard_M32ms_v2" => {'numberOfCores' => 32, 'memoryInMB' => 896000},
      "Standard_M64ms_v2" => {'numberOfCores' => 64, 'memoryInMB' => 1835008},
      "Standard_M64s_v2" => {'numberOfCores' => 64, 'memoryInMB' => 1048576},
      "Standard_M128ms_v2" => {'numberOfCores' => 128, 'memoryInMB' => 3985408},
      "Standard_M128s_v2" => {'numberOfCores' => 128, 'memoryInMB' => 2097152},
      "Standard_M192ims_v2" => {'numberOfCores' => 192, 'memoryInMB' => 4194304},
      "Standard_M192is_v2" => {'numberOfCores' => 192, 'memoryInMB' => 2097152},
      "Standard_M32dms_v2" => {'numberOfCores' => 32, 'memoryInMB' => 896000},
      "Standard_M64dms_v2" => {'numberOfCores' => 64, 'memoryInMB' => 1835008},
      "Standard_M64ds_v2" => {'numberOfCores' => 64, 'memoryInMB' => 1048576},
      "Standard_M128dms_v2" => {'numberOfCores' => 128, 'memoryInMB' => 3985408},
      "Standard_M128ds_v2" => {'numberOfCores' => 128, 'memoryInMB' => 2097152},
      "Standard_M192idms_v2" => {'numberOfCores' => 192, 'memoryInMB' => 4194304},
      "Standard_M192ids_v2" => {'numberOfCores' => 192, 'memoryInMB' => 2097152},
      "Standard_A0" => {'numberOfCores' => 1, 'memoryInMB' => 768},
      "Standard_A1" => {'numberOfCores' => 1, 'memoryInMB' => 1792},
      "Standard_A2" => {'numberOfCores' => 2, 'memoryInMB' => 3584},
      "Standard_A3" => {'numberOfCores' => 4, 'memoryInMB' => 7168},
      "Standard_A5" => {'numberOfCores' => 2, 'memoryInMB' => 14336},
      "Standard_A4" => {'numberOfCores' => 8, 'memoryInMB' => 14336},
      "Standard_A6" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_A7" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Basic_A0" => {'numberOfCores' => 1, 'memoryInMB' => 768},
      "Basic_A1" => {'numberOfCores' => 1, 'memoryInMB' => 1792},
      "Basic_A2" => {'numberOfCores' => 2, 'memoryInMB' => 3584},
      "Basic_A3" => {'numberOfCores' => 4, 'memoryInMB' => 7168},
      "Basic_A4" => {'numberOfCores' => 8, 'memoryInMB' => 14336},
      "Standard_D1" => {'numberOfCores' => 1, 'memoryInMB' => 3584},
      "Standard_D2" => {'numberOfCores' => 2, 'memoryInMB' => 7168},
      "Standard_D3" => {'numberOfCores' => 4, 'memoryInMB' => 14336},
      "Standard_D4" => {'numberOfCores' => 8, 'memoryInMB' => 28672},
      "Standard_D11" => {'numberOfCores' => 2, 'memoryInMB' => 14336},
      "Standard_D12" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_D13" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Standard_D14" => {'numberOfCores' => 16, 'memoryInMB' => 114688},
      "Standard_DS1" => {'numberOfCores' => 1, 'memoryInMB' => 3584},
      "Standard_DS2" => {'numberOfCores' => 2, 'memoryInMB' => 7168},
      "Standard_DS3" => {'numberOfCores' => 4, 'memoryInMB' => 14336},
      "Standard_DS4" => {'numberOfCores' => 8, 'memoryInMB' => 28672},
      "Standard_DS11" => {'numberOfCores' => 2, 'memoryInMB' => 14336},
      "Standard_DS12" => {'numberOfCores' => 4, 'memoryInMB' => 28672},
      "Standard_DS13" => {'numberOfCores' => 8, 'memoryInMB' => 57344},
      "Standard_DS14" => {'numberOfCores' => 16, 'memoryInMB' => 114688},
      "Standard_M208ms_v2" => {'numberOfCores' => 208, 'memoryInMB' => 5836800},
      "Standard_M208s_v2" => {'numberOfCores' => 208, 'memoryInMB' => 2918400},
      "Standard_M416-208s_v2" => {'numberOfCores' => 416, 'memoryInMB' => 5836800},
      "Standard_M416s_v2" => {'numberOfCores' => 416, 'memoryInMB' => 5836800},
      "Standard_M416-208ms_v2" => {'numberOfCores' => 416, 'memoryInMB' => 11673600},
      "Standard_M416ms_v2" => {'numberOfCores' => 416, 'memoryInMB' => 11673600},
      "Standard_M416s_8_v2" => {'numberOfCores' => 416, 'memoryInMB' => 7782400},
      "Standard_L8s_v3" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_L16s_v3" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_L32s_v3" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_L48s_v3" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_L64s_v3" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_L80s_v3" => {'numberOfCores' => 80, 'memoryInMB' => 655360},
      "Standard_DC8_v2" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_DC1s_v2" => {'numberOfCores' => 1, 'memoryInMB' => 4096},
      "Standard_DC2s_v2" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_DC4s_v2" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_E80is_v4" => {'numberOfCores' => 80, 'memoryInMB' => 516096},
      "Standard_E80ids_v4" => {'numberOfCores' => 80, 'memoryInMB' => 516096},
      "Standard_HB120-16rs_v2" => {'numberOfCores' => 120, 'memoryInMB' => 466944},
      "Standard_HB120-32rs_v2" => {'numberOfCores' => 120, 'memoryInMB' => 466944},
      "Standard_HB120-64rs_v2" => {'numberOfCores' => 120, 'memoryInMB' => 466944},
      "Standard_HB120-96rs_v2" => {'numberOfCores' => 120, 'memoryInMB' => 466944},
      "Standard_HB120rs_v2" => {'numberOfCores' => 120, 'memoryInMB' => 466944},
      "Standard_D2a_v4" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4a_v4" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8a_v4" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16a_v4" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32a_v4" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48a_v4" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64a_v4" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D96a_v4" => {'numberOfCores' => 96, 'memoryInMB' => 393216},
      "Standard_D2as_v4" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4as_v4" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8as_v4" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16as_v4" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32as_v4" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48as_v4" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64as_v4" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D96as_v4" => {'numberOfCores' => 96, 'memoryInMB' => 393216},
      "Standard_E2a_v4" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4a_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8a_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16a_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20a_v4" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32a_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48a_v4" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64a_v4" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96a_v4" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E2as_v4" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4-2as_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E4as_v4" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8-2as_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8-4as_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8as_v4" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16-4as_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16-8as_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16as_v4" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20as_v4" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32-8as_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32-16as_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32as_v4" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48as_v4" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64-16as_v4" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64-32as_v4" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64as_v4" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96-24as_v4" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96-48as_v4" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96as_v4" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_D2as_v5" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4as_v5" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8as_v5" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16as_v5" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32as_v5" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48as_v5" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64as_v5" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D96as_v5" => {'numberOfCores' => 96, 'memoryInMB' => 393216},
      "Standard_E2as_v5" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4-2as_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E4as_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8-2as_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8-4as_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8as_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16-4as_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16-8as_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16as_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20as_v5" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32-8as_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32-16as_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32as_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48as_v5" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64-16as_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64-32as_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64as_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96-24as_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96-48as_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96as_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E112ias_v5" => {'numberOfCores' => 112, 'memoryInMB' => 688128},
      "Standard_D2ads_v5" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_D4ads_v5" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_D8ads_v5" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_D16ads_v5" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_D32ads_v5" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_D48ads_v5" => {'numberOfCores' => 48, 'memoryInMB' => 196608},
      "Standard_D64ads_v5" => {'numberOfCores' => 64, 'memoryInMB' => 262144},
      "Standard_D96ads_v5" => {'numberOfCores' => 96, 'memoryInMB' => 393216},
      "Standard_E2ads_v5" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_E4-2ads_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E4ads_v5" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_E8-2ads_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8-4ads_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E8ads_v5" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_E16-4ads_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16-8ads_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E16ads_v5" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_E20ads_v5" => {'numberOfCores' => 20, 'memoryInMB' => 163840},
      "Standard_E32-8ads_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32-16ads_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E32ads_v5" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_E48ads_v5" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_E64-16ads_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64-32ads_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E64ads_v5" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_E96-24ads_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96-48ads_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E96ads_v5" => {'numberOfCores' => 96, 'memoryInMB' => 688128},
      "Standard_E112iads_v5" => {'numberOfCores' => 112, 'memoryInMB' => 688128},
      "Standard_B2als_v2" => {'numberOfCores' => 2, 'memoryInMB' => 4096},
      "Standard_B2as_v2" => {'numberOfCores' => 2, 'memoryInMB' => 8192},
      "Standard_B2ats_v2" => {'numberOfCores' => 2, 'memoryInMB' => 1024},
      "Standard_B4als_v2" => {'numberOfCores' => 4, 'memoryInMB' => 8192},
      "Standard_B4as_v2" => {'numberOfCores' => 4, 'memoryInMB' => 16384},
      "Standard_B8als_v2" => {'numberOfCores' => 8, 'memoryInMB' => 16384},
      "Standard_B8as_v2" => {'numberOfCores' => 8, 'memoryInMB' => 32768},
      "Standard_B16als_v2" => {'numberOfCores' => 16, 'memoryInMB' => 32768},
      "Standard_B16as_v2" => {'numberOfCores' => 16, 'memoryInMB' => 65536},
      "Standard_B32als_v2" => {'numberOfCores' => 32, 'memoryInMB' => 65536},
      "Standard_B32as_v2" => {'numberOfCores' => 32, 'memoryInMB' => 131072},
      "Standard_L8as_v3" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_L16as_v3" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_L32as_v3" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_L48as_v3" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_L64as_v3" => {'numberOfCores' => 64, 'memoryInMB' => 524288},
      "Standard_L80as_v3" => {'numberOfCores' => 80, 'memoryInMB' => 655360},
      "Standard_NV4as_v4" => {'numberOfCores' => 4, 'memoryInMB' => 14336},
      "Standard_NV8as_v4" => {'numberOfCores' => 8, 'memoryInMB' => 28672},
      "Standard_NV16as_v4" => {'numberOfCores' => 16, 'memoryInMB' => 57344},
      "Standard_NV32as_v4" => {'numberOfCores' => 32, 'memoryInMB' => 114688},
      "Standard_G1" => {'numberOfCores' => 2, 'memoryInMB' => 28672},
      "Standard_G2" => {'numberOfCores' => 4, 'memoryInMB' => 57344},
      "Standard_G3" => {'numberOfCores' => 8, 'memoryInMB' => 114688},
      "Standard_G4" => {'numberOfCores' => 16, 'memoryInMB' => 229376},
      "Standard_G5" => {'numberOfCores' => 32, 'memoryInMB' => 458752},
      "Standard_GS1" => {'numberOfCores' => 2, 'memoryInMB' => 28672},
      "Standard_GS2" => {'numberOfCores' => 4, 'memoryInMB' => 57344},
      "Standard_GS3" => {'numberOfCores' => 8, 'memoryInMB' => 114688},
      "Standard_GS4" => {'numberOfCores' => 16, 'memoryInMB' => 229376},
      "Standard_GS4-4" => {'numberOfCores' => 16, 'memoryInMB' => 229376},
      "Standard_GS4-8" => {'numberOfCores' => 16, 'memoryInMB' => 229376},
      "Standard_GS5" => {'numberOfCores' => 32, 'memoryInMB' => 458752},
      "Standard_GS5-8" => {'numberOfCores' => 32, 'memoryInMB' => 458752},
      "Standard_GS5-16" => {'numberOfCores' => 32, 'memoryInMB' => 458752},
      "Standard_L4s" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_L8s" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_L16s" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_L32s" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_NV6ads_A10_v5" => {'numberOfCores' => 6, 'memoryInMB' => 56320},
      "Standard_NV12ads_A10_v5" => {'numberOfCores' => 12, 'memoryInMB' => 112640},
      "Standard_NV18ads_A10_v5" => {'numberOfCores' => 18, 'memoryInMB' => 225280},
      "Standard_NV36adms_A10_v5" => {'numberOfCores' => 36, 'memoryInMB' => 901120},
      "Standard_NV36ads_A10_v5" => {'numberOfCores' => 36, 'memoryInMB' => 450560},
      "Standard_NV72ads_A10_v5" => {'numberOfCores' => 72, 'memoryInMB' => 901120},
      "Standard_NC6s_v3" => {'numberOfCores' => 6, 'memoryInMB' => 114688},
      "Standard_NC12s_v3" => {'numberOfCores' => 12, 'memoryInMB' => 229376},
      "Standard_NC24rs_v3" => {'numberOfCores' => 24, 'memoryInMB' => 458752},
      "Standard_NC24s_v3" => {'numberOfCores' => 24, 'memoryInMB' => 458752},
      "Standard_NC24ads_A100_v4" => {'numberOfCores' => 24, 'memoryInMB' => 225280},
      "Standard_NC48ads_A100_v4" => {'numberOfCores' => 48, 'memoryInMB' => 450560},
      "Standard_NC96ads_A100_v4" => {'numberOfCores' => 96, 'memoryInMB' => 901120},
      "Standard_DC1s_v3" => {'numberOfCores' => 1, 'memoryInMB' => 8192},
      "Standard_DC2s_v3" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_DC4s_v3" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_DC8s_v3" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_DC16s_v3" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_DC24s_v3" => {'numberOfCores' => 24, 'memoryInMB' => 196608},
      "Standard_DC32s_v3" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_DC48s_v3" => {'numberOfCores' => 48, 'memoryInMB' => 393216},
      "Standard_DC1ds_v3" => {'numberOfCores' => 1, 'memoryInMB' => 8192},
      "Standard_DC2ds_v3" => {'numberOfCores' => 2, 'memoryInMB' => 16384},
      "Standard_DC4ds_v3" => {'numberOfCores' => 4, 'memoryInMB' => 32768},
      "Standard_DC8ds_v3" => {'numberOfCores' => 8, 'memoryInMB' => 65536},
      "Standard_DC16ds_v3" => {'numberOfCores' => 16, 'memoryInMB' => 131072},
      "Standard_DC24ds_v3" => {'numberOfCores' => 24, 'memoryInMB' => 196608},
      "Standard_DC32ds_v3" => {'numberOfCores' => 32, 'memoryInMB' => 262144},
      "Standard_DC48ds_v3" => {'numberOfCores' => 48, 'memoryInMB' => 393216}
  }
  
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

      puts "Raw Azure VM Data: #{vms.inspect}"
  
      vms.map do |vm|
        # STDERR.puts "Processing VM: #{vm['name']}"
        # STDERR.puts "VM Size: #{vm.dig("properties", "hardwareProfile", "vmSize")}"
        private_ips = []
        public_ips = []
        vm["properties"]["networkProfile"]["networkInterfaces"].each do |nic|
            private_ip, public_ip = get_vm_ip_addresses(subscription, nic["id"])
            private_ips += private_ip
            public_ips += public_ip
        end

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
            ip_addresses: [private_ips, public_ips],
            fqdn: vm.dig("properties", "dnsSettings", "fqdn"),
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
      formatted_vms = all_vms.map do |vm|
        vm_size = vm[:vm_size]
        size_details = VM_SIZE_MAPPING[vm_size] || {}
        {
          host_name: vm[:host_name],
          ip_addresses: vm[:ip_addresses][0] + vm[:ip_addresses][1], 
          description: "Azure VM", 
          operating_system: vm[:operating_system] || "N/A",
          operating_system_version: vm[:operating_system_version] || "N/A",
          fqdn: vm[:fqdn] || "N/A",
          # assigned_id: vm[:assigned_id] || "N/A",
          custom_fields: {
            location: vm[:location],
            operating_system_name: vm[:operating_system] || "N/A"
          },
          ram_allocated_gb: size_details['memoryInMB'] ? (size_details['memoryInMB'] / 1024).to_i : nil,
          cpu_count: size_details['numberOfCores'] || "N/A",
          storage_allocated_gb: vm[:storage_allocated_gb] || "N/A"
        }
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
