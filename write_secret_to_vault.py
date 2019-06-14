#!/usr/bin/env python
"""
"""

import os
import requests
# https://stackoverflow.com/questions/27981545/suppress-insecurerequestwarning-unverified-https-request-is-being-made-in-pytho
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

import argparse
import json

logfile = '/tmp/readdb.log'

#______________________________________
def cli_options():
  parser = argparse.ArgumentParser(description='Vault connector')
  parser.add_argument('-v', '--vault-url', dest='vault_url', help='Vault endpoint')
  parser.add_argument('-w', '--wrapping-token', dest='wrapping_token', help='Wrapping Token')
  parser.add_argument('-s', '--secret-path', dest='secret_path', help='Secret path on vault')
  parser.add_argument('--key', dest='user_key', default='luks', help='Vault user key name')
  parser.add_argument('--value', dest='user_value', help='Vault user key value, i.e. passphrase')
  return parser.parse_args()


#______________________________________
def unwrap_vault_token(url, wrapping_token):

  url = url + '/v1/sys/wrapping/unwrap'

  headers = { "X-Vault-Token": wrapping_token }

  response = requests.post(url, headers=headers, verify=False)

  response.raise_for_status()

  deserialized_response = json.loads(response.text)

  try:
    deserialized_response["auth"]["client_token"]
  except KeyError:
    raise Exception("[FATAL] Unable to unwrap vault token.")

  return deserialized_response["auth"]["client_token"]

#______________________________________
def post_secret(url, path, token, key, value):

  url = url + '/v1/secrets/data/' + path

  headers = { "X-Vault-Token": token }

  data = '{ "options": { "cas": 0 }, "data": { "'+key+'": "'+value+'"} }'

  response = requests.post(url, headers=headers, data=data, verify=False)

  response.raise_for_status()

  deserialized_response = json.loads(response.text)
    
  try:
    deserialized_response["data"]
  except KeyError:
    raise Exception("[FATAL] Unable to write vault path.")

  return deserialized_response

#______________________________________
def parse_response(response):

  if not response["data"]["created_time"]:
    raise Exception("No cretation time")

  if response["data"]["destroyed"] != False:
    raise Exception("Token already detroyed")

  if response["data"]["version"] != 1:
    raise Exception("Token not at 1st verion")

  if response["data"]["deletion_time"] != "":
    raise Exception("Token aready deleted")

  return 0

#______________________________________
def revoke_token(url, token):

  url = url + '/v1/auth/token/revoke-self'

  headers = { "X-Vault-Token": token }

  response = requests.post( url, headers=headers, verify=False )

#______________________________________
def write_secret_to_vault():

  options = cli_options()

  # Check vault
  r = requests.get(options.vault_url)
  r.raise_for_status()

  write_token = unwrap_vault_token( options.vault_url, options.wrapping_token )

  response_output = post_secret( options.vault_url, options.secret_path, write_token, options.user_key, options.user_value )

  parse_response( response_output )

  revoke_token( options.vault_url, write_token )

#______________________________________
if __name__ == '__main__':
  write_secret_to_vault()
