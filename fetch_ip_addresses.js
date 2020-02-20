#!/usr/bin/env node
let http = require("https");

/// To use this script, fill in API_TOKEN, SUBDOMAIN, and TAG_NAME with the appropriate information
// Read the guides to learn how to generate an API_TOKEN. https://guides.tidalmg.com/authenticate.html
const API_TOKEN = "token";
// Your tidalmg subdomain. ex: 'subdomain.tidalmg.com'
const SUBDOMAIN = "subdomain"
// Requires full name
const TAG_NAME = "tag";

// Boiler plate to promisify web request
// Inspired from https://stackoverflow.com/a/55214702/5785789
function httpRequest(method, url, body = null) {
  if (!['get', 'post', 'head'].includes(method)) {
    throw new Error(`Invalid method: ${method}`);
  }

  let urlObject;
  return new Promise((resolve, reject) => {
    try {
      urlObject = new URL(url);
    } catch (error) {
      reject(Error(`Invalid url ${url}`));
    }

    if (body && method !== 'post') {
      reject(Error(`Invalid use of the body parameter while using the ${method.toUpperCase()} method.`));
    }

    const clientRequest = http.request(urlObject, {headers: {authorization: "Bearer " + API_TOKEN,
                                                             accept: "application/json"}}, incomingMessage => {

      // Response object.
      let response = [];
      // Collect response body data.

      incomingMessage.on('data', chunk => {
        response.push(chunk);
      });

      // Resolve on end.
      incomingMessage.on('end', () => {
        if (response.length) {;
          try {
            response = JSON.parse(Buffer.concat(response));
          } catch (error) {
            reject(error);
            // Silently fail if response is not JSON.
          }
        }

        resolve(response);
      });
    });

    // Reject on request error.
    clientRequest.on('error', error => {
      reject(error);
    });

    // Write request body if present.
    if (body) {
      clientRequest.write(body);
    }

    // Close HTTP connection.
    clientRequest.end();
  });
}
// 1 - Find the tag you want:

httpRequest("get", `https://${SUBDOMAIN}.tidalmg.com/api/v1/tags?search=${TAG_NAME}`)
// 2 - Get all the applications with that tag:
  .then(res => {
    let id = res[0].id;
    return httpRequest("get", `https://${SUBDOMAIN}.tidalmg.com/api/v1/apps?tag_id=${res[0].id}`);
  })
// 3 - For each app ID get all the dependencies for each application
  .then(res => {
    return new Promise((resolve, reject) => {
      Promise.all(res.map(app => {
        return httpRequest("get", `https://${SUBDOMAIN}.tidalmg.com/api/v1/apps/${app.id}/dependencies`);
      }))
        .then(res => resolve(res));
    });
  })
// 4 - For each server dependencies for the application, get all it’s IP addresses
  .then(res => {
    return new Promise((resolve, reject) => {
      let servers = res.reduce((accumulator, resource) => {
        resource.children.forEach(child => {
          if (child.type === 'Server'){
            accumulator.add(child.id);
          }
        });
        return accumulator;
        // Use set to ensure unique ids
      }, new Set());
      // Convert set to array and map over
      Promise.all([...servers].map(server => {

        // console.log(server);
        return httpRequest("get", `https://${SUBDOMAIN}.tidalmg.com/api/v1/servers/${server}`);
      }))
        .then(res => resolve(res));
    });
  })
// Print out each unique ip address as a new line delimited list
  .then(res => {
    let ip_addresses = new Set();
    res.forEach(server => {
      server.ip_addresses.map(ip => ip_addresses.add(ip.address));
    });
    ip_addresses.forEach(address => console.log(address));
  })
  .catch(error => console.error(error));
