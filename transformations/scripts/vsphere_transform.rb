#!/usr/bin/env ruby

require 'json'

def transform(input)
  json = JSON.parse(input)
  data = {servers: []}
  json["VirtualMachines"].each do |vm|
    props = {}
    
    config = vm["Summary"]["Config"]
    stats = vm["Summary"]["QuickStats"]
    storage = vm["Summary"]["Storage"]
    hostruntime = vm["Summary"]["Runtime"]["Host"]
    run = vm["Runtime"]
    guest = vm["Guest"]

    props[:fqdn] = guest["Hostname"]
    props[:operating_system] = guest["GuestFullName"]
    props[:host_name] = config["Name"]
    props[:description] = config["Annotation"]
    props[:assigned_id] = config["Uuid"]
    props[:ram_allocated_gb] = config["MemorySizeMB"].to_f / 1024    
    props[:ram_used_gb] = stats["GuestMemoryUsage"].to_f / 1024
    props[:cpu_count] = config["NumCpu"]
    props[:storage_used_gb] = storage["Committed"].to_f / 2**(10*3)
    props[:storage_allocated_gb] = (storage["Committed"].to_f + storage["Uncommitted"].to_f) / 2**(10*3)
    props[:virtual] = true
    props[:cpu_name] = hostruntime["host"] ? hostruntime["host"]["Summary"]["Hardware"]["CpuModel"] : nil
    props[:operating_system_version] = nil
    props[:ip_addresses] = guest["Net"].map do |net| { address: net["IpAddress"] }  end

    custom = {status:  stats["GuestHeartbeatStatus"],
              product: config["Product"] ? config["Product"]["Name"] : false }
    props[:custom_fields] = custom

    data[:servers].push props
  end
  data
end

# Read in data from STDIN
data = STDIN.read

# Transform data
output = transform data

# Output transformed data to STDOUT
puts JSON.generate output
