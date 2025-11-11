#!/bin/bash

# Google Play Internal App Sharing Upload Script
# Fixes fastlane upload_to_play_store_internal_app_sharing 404 issues

set -e

# Check required parameters
if [ $# -ne 2 ]; then
    echo "Usage: $0 <aab_file_path> <package_name>"
    echo "Environment variables required:"
    echo "  GOOGLE_PLAY_KEY_FILE_PATH - path to service account JSON"
    exit 1
fi

AAB_FILE_PATH="$1"
PACKAGE_NAME="$2"

# Check required environment variables
if [ -z "$GOOGLE_PLAY_KEY_FILE_PATH" ]; then
    echo "Error: GOOGLE_PLAY_KEY_FILE_PATH environment variable is required"
    exit 1
fi

if [ ! -f "$GOOGLE_PLAY_KEY_FILE_PATH" ]; then
    echo "Error: Service account JSON file not found at $GOOGLE_PLAY_KEY_FILE_PATH"
    exit 1
fi

if [ ! -f "$AAB_FILE_PATH" ]; then
    echo "Error: AAB file not found at $AAB_FILE_PATH"
    exit 1
fi

echo "Starting Internal App Sharing upload..."
echo "AAB file: $AAB_FILE_PATH"
echo "Package: $PACKAGE_NAME"

# Extract authentication details from service account JSON
AUTH_ISS=$(cat "$GOOGLE_PLAY_KEY_FILE_PATH" | grep -o '"client_email"[^,]*' | cut -d '"' -f 4)
AUTH_AUD=$(cat "$GOOGLE_PLAY_KEY_FILE_PATH" | grep -o '"token_uri"[^,]*' | cut -d '"' -f 4)
AUTH_SCOPE="https://www.googleapis.com/auth/androidpublisher"

# Extract private key (handle multi-line properly)
PRIVATE_KEY=$(cat "$GOOGLE_PLAY_KEY_FILE_PATH" | jq -r '.private_key')

if [ -z "$AUTH_ISS" ] || [ -z "$AUTH_AUD" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "Error: Failed to extract authentication details from service account JSON"
    exit 1
fi

echo "Extracted service account details successfully"

# Create JWT header and payload
JWT_HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# JWT payload with current timestamp
NOW=$(date +%s)
EXPIRES=$((NOW + 3600))  # 1 hour expiration

JWT_PAYLOAD=$(echo -n "{\"iss\":\"$AUTH_ISS\",\"scope\":\"$AUTH_SCOPE\",\"aud\":\"$AUTH_AUD\",\"exp\":$EXPIRES,\"iat\":$NOW}" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# Create signature input
SIGNATURE_INPUT="$JWT_HEADER.$JWT_PAYLOAD"

# Create private key file temporarily
TEMP_KEY_FILE=$(mktemp)
echo "$PRIVATE_KEY" > "$TEMP_KEY_FILE"

# Sign with private key
SIGNATURE=$(echo -n "$SIGNATURE_INPUT" | openssl dgst -sha256 -sign "$TEMP_KEY_FILE" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# Clean up temporary key file
rm "$TEMP_KEY_FILE"

# Construct final JWT
JWT="$JWT_HEADER.$JWT_PAYLOAD.$SIGNATURE"

echo "Generated JWT successfully"

# Get access token
echo "Requesting access token..."
TOKEN_RESPONSE=""
for attempt in 1 2 3 4 5; do
    echo "Attempt $attempt: Requesting access token..."
    TOKEN_RESPONSE=$(curl --retry 5 --retry-delay 10 --continue-at - -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$JWT" \
        "$AUTH_AUD")
    
    if [ $? -eq 0 ] && [ -n "$TOKEN_RESPONSE" ]; then
        break
    else
        echo "Attempt $attempt failed. Retrying in 10 seconds..."
        sleep 10
    fi
done

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: Failed to get access token"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "Access token obtained successfully"

# Upload AAB to Internal App Sharing
echo "Uploading AAB to Internal App Sharing..."

UPLOAD_URL="https://www.googleapis.com/upload/androidpublisher/v3/applications/internalappsharing/$PACKAGE_NAME/artifacts/bundle?uploadType=media"

HTTP_RESPONSE=""
for attempt in 1 2 3 4 5; do
    echo "Attempt $attempt: Uploading AAB file..."
    HTTP_RESPONSE=$(curl --retry 5 --retry-delay 10 --continue-at - -w "HTTPSTATUS:%{http_code}" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -X POST \
        --data-binary "@$AAB_FILE_PATH" \
        "$UPLOAD_URL")
    
    if [ $? -eq 0 ] && [ -n "$HTTP_RESPONSE" ]; then
        break
    else
        echo "Attempt $attempt failed. Retrying in 10 seconds..."
        sleep 10
    fi
done

# Parse response
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -E 's/HTTPSTATUS:[0-9]{3}$//')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

echo "Upload completed with status: $HTTP_STATUS"

if [ "$HTTP_STATUS" != "200" ]; then
    echo "Error: Upload failed"
    echo "Status: $HTTP_STATUS"
    echo "Response: $HTTP_BODY"
    exit 1
fi

# Extract download URL from response
DOWNLOAD_URL=$(echo "$HTTP_BODY" | jq -r '.downloadUrl')

if [ "$DOWNLOAD_URL" = "null" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Failed to extract download URL from response"
    echo "Response: $HTTP_BODY"
    exit 1
fi

echo "=========================================="
echo "SUCCESS: Internal App Sharing Upload Complete"
echo "Download URL: $DOWNLOAD_URL"
echo "=========================================="

# Output for GitHub Actions
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "url=$DOWNLOAD_URL" >> "$GITHUB_OUTPUT"
    echo "package_name=$PACKAGE_NAME" >> "$GITHUB_OUTPUT"
fi

# Output for GitHub Actions Job Summary
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
    echo "## 🚀 Internal App Sharing Upload Complete" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
    echo "**Package:** \`$PACKAGE_NAME\`" >> "$GITHUB_STEP_SUMMARY"
    echo "**Download URL:** $DOWNLOAD_URL" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
    
    # Generate QR code for easy mobile access
    QR_URL="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$(echo "$DOWNLOAD_URL" | sed 's/ /%20/g')"
    echo "### 📱 QR Code for Mobile Download" >> "$GITHUB_STEP_SUMMARY"
    echo "![QR Code]($QR_URL)" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
    echo "Share this link with your testers to download the app directly from Google Play." >> "$GITHUB_STEP_SUMMARY"
fi

echo "Script completed successfully"