#!/bin/bash

# Dependencies: jq and curl

CONFIG_FILE=".token" # Change to your filename

# 1. Parse configuration values
KEYCLOAK_URL=$(jq -r '.keycloak_url' "$CONFIG_FILE")
REALM=$(jq -r '.realm' "$CONFIG_FILE")
SCOPES=$(jq -r '.requested_scopes | join(" ")' "$CONFIG_FILE")

# 2. Ask user for credentials (so they aren't hardcoded)
read -p "Enter Client ID: " CLIENT_ID
read -sp "Enter Client Secret: " CLIENT_SECRET
echo ""

# 3. Construct the Token Endpoint
TOKEN_ENDPOINT="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token"

# 4. Fetch the token and extract the access_token string
ACCESS_TOKEN=$(curl -s -X POST "$TOKEN_ENDPOINT" \
	-H "Content-Type: application/x-www-form-urlencoded" \
	-d "grant_type=client_credentials" \
	-d "client_id=${CLIENT_ID}" \
	-d "client_secret=${CLIENT_SECRET}" \
	-d "scope=${SCOPES}" | jq -r '.access_token')

# 5. Output the result or use it
if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
	echo "🔑 Token successfully retrieved!"
	echo "--------------------------------"
	echo "$ACCESS_TOKEN"
else
	echo "❌ Failed to retrieve token. Check your credentials or network."
fi
