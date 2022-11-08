#!/usr/bin/env bash

# will be prompted to provide login details to vsphere
tidal login vsphere

# will be prompted to provide tidal workspace login details
tidal login

tidal get vsphere > vsphere_data.json

# Configure proxy for internet access
# change https://proxy_url.com to the URL, including user/pass if needed for your proxy server.
export https_proxy=https://proxy_url.com

# transform vsphere data and sync data with Tidal
cat vsphere_data.json | ./scripts/vsphere_transform.rb | tidal sync servers

#unset proxy config in order to leave config as it was before running
export https_proxy=""
