#!/usr/bin/env ruby
require 'csv'
require 'json'

# Define the input and output file paths
input_file = 'input.csv'
output_file = 'output.json'

# Define the column names to extract from the CSV file
hostname_col = 'Server Name'
ram_col = 'OnPrem RAM(GB)'
cpus_col = 'OnPrem Cores'

# Read the CSV file and extract the required columns
data = []
CSV.foreach(input_file, headers: true) do |row|
  if  row[ram_col].to_i > 0 || row[cpus_col].to_i > 0 
    hostname = row[hostname_col]
    ram_gb = row[ram_col].to_i 
    cpu_count = row[cpus_col].to_i 

    # Generate a JSON object with the required structure
    json_obj = {
      "host_name": hostname,
      "ram_allocated_gb": ram_gb,
      "cpu_count": cpu_count,
    }

    # Add the JSON object to the array
    data << json_obj
  end
end

# Write the array of JSON objects to the output file
File.open(output_file, 'w') do |f|
  f.write(JSON.pretty_generate({servers: data}))
end

