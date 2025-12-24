#!/bin/bash

## Created by Trenton Cook
## Created on 2025-12-22
## Version 1.1

## VARIABLES

## DO NOT CHANGE
scriptURL="$JAMF_URL/api/v1/scripts"
startTime=$(date +%s)

## CHANGE IF NEEDED
debugMode="true"

## FUNCTIONS

debug() {
    if [[ "$debugMode" == "true" ]]; then
        echo $@
    fi
}

normalizeKey() {
    echo "$1" | tr '[:upper:]' '[:lower:]' \
    | tr ' ' '_' \
    | tr -d '(' \
    | tr -d ')' \
    | tr -d '{' \
    | tr -d '}' \
    | tr -d '[' \
    | tr -d ']' \
    | tr -d '"' \
    | tr -d "'"
}

normalizeContent() {
    local contentToNormalize="$1"
    echo "$contentToNormalize" | tr -d '\r' | sed 's/[[:space:]]*$//'
}

getBearerToken() {
    local responseBody
    responseBody=$(curl -s --location --request POST "$JAMF_URL/api/oauth/token" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "client_secret=$CLIENT_SECRET" \
    )

    bearerToken=$(echo $responseBody | jq -r '.access_token // empty')

    if [[ -z "$bearerToken" ]]; then
        debug "FAILURE: Bearer token could not be retrieved"
        exit 1
    else
        debug "Bearer Token retrieved successfully"
    fi
}

invalidateToken() {
    local responseBody

    responseBody=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $JAMF_URL/api/v1/auth/invalidate-token -X POST -s -o /dev/null)

    if [[ ${responseBody} != 204 ]]; then
        debug "FAILURE: Bearer token could not be invalidated"
        return 1
    else
        debug "Bearer Token invalidated successfully"
    fi

    bearerToken=""
}

buildLocalInventory() {
    declare -gA localInventory
    debug "-- Building local inventory --"

    for script in "$WORKING_DIRECTORY"/*.sh; do
        [[ -f "$script" ]] || continue
        localScriptName="$(basename "$script" .sh)"
        nameKey=$(normalizeKey "$localScriptName")
        localInventory["$nameKey"]="$script"

        debug "Added $localScriptName to localInventory"
    done

    debug "-- Local inventory built --"
}

buildJamfInventory() {
    declare -gA jamfInventory
    debug "-- Building Jamf inventory --"
    debug "-- Retrieving Jamf scripts --"
    jamfScriptBuild=$(curl -s -H "Authorization: Bearer ${bearerToken}" "$scriptURL?page=0&page-size=2000")

    while IFS=$'\t' read -r name id; do
        key=$(normalizeKey "$name")
        jamfInventory["$key"]="$id"
        debug "Added $name to jamfInventory"
    done < <(
        echo "$jamfScriptBuild" | jq -r '.results[] | "\(.name)\t\(.id)"'
    )

    debug "-- Jamf inventory built --"
}

compareInventories() {
    debug "-- Comparing inventories --"

    local changesFound="false"
    local allKeys=()

    # Collect all keys
    for k in "${!localInventory[@]}"; do allKeys+=("$k"); done
    for k in "${!jamfInventory[@]}"; do allKeys+=("$k"); done
    readarray -t allKeys < <(printf "%s\n" "${allKeys[@]}" | sort -u)

    for key in "${allKeys[@]}"; do
        local localVal="${localInventory[$key]:-<missing>}"
        local jamfVal="${jamfInventory[$key]:-<missing>}"

        if [[ "$localVal" == "<missing>" ]]; then
            echo ""
            echo "Missing locally: $key"
            echo "  Jamf ID: $jamfVal"
            downloadFromJamf "$key"
            changesFound="true"
        elif [[ "$jamfVal" == "<missing>" ]]; then
            echo ""
            echo "Missing in Jamf: $key"
            echo "  Local Path: $localVal"
            uploadToJamf "$key"
            changesFound="true"
        else
            retrieveLocalScriptContent "$key"
            retrieveJamfScriptContent "$key"

            if [[ "$localScriptContent" != "$jamfScriptContent" ]]; then
                echo ""
                echo "Content mismatch: $key"
                echo "  Local Path: $localVal"
                echo "  Jamf ID:    $jamfVal"
                changesFound="true"

                if [[ "$debugMode" == "true" ]]; then
                    debug "Would have updated Jamf with local script '$key'"
                else
                    updateJamf "$key"
                fi
            fi
        fi
    done

    if [[ "$changesFound" != "true" ]]; then
        echo "No mismatches or missing scripts detected"
    fi

    debug "-- Inventory comparison complete --"
}

downloadFromJamf() {
    local key="$1"
    local scriptID="${jamfInventory[$key]}"
    local filePath="$WORKING_DIRECTORY/$key.sh"

    if [[ -z "$scriptID" ]]; then
        debug "Cannot download $key: No Jamf ID found"
        return 1
    fi

    if [[ "$debugMode" == "true" ]]; then
        debug "Would have downloaded script '$key' from Jamf (ID: $scriptID) to $filePath"
        return 0
    fi

    debug "Downloading script '$key' from Jamf (ID: $scriptID) to $filePath"

    jamfScriptContent=$(curl -s -H "Authorization: Bearer ${bearerToken}" \
        "$scriptURL/$scriptID" | jq -r '.scriptContents // empty')

    if [[ -z "$jamfScriptContent" ]]; then
        echo "Failed to retrieve content for $key from Jamf"
        return 1
    fi

    printf "%s\n" "$jamfScriptContent" > "$filePath"
    echo "Downloaded $key from Jamf to $filePath"
}

uploadToJamf() {
    local key="$1"
    local localPath="${localInventory[$key]}"

    if [[ ! -f "$localPath" ]]; then
        debug "Cannot upload $key: Local file not found at $localPath"
        return 1
    fi

    if [[ "$debugMode" == "true" ]]; then
        debug "Would have uploaded script '$key' from $localPath to Jamf"
        return 0
    fi

    debug "Uploading script '$key' from $localPath to Jamf"

    local localScriptContent
    localScriptContent=$(cat "$localPath")

    # Escape for JSON
    local escapedContent
    escapedContent=$(jq -Rs '.' <<< "$localScriptContent")

    curl -s -X POST "$scriptURL" \
        -H "Authorization: Bearer ${bearerToken}" \
        -H "Content-Type: application/json" \
        -d @- <<-EOF
    {
        "name": "$key",
        "info": "",
        "notes": "",
        "priority": "AFTER",
        "categoryId": "1",
        "parameter4": "",
        "parameter5": "",
        "parameter6": "",
        "parameter7": "",
        "parameter8": "",
        "parameter9": "",
        "parameter10": "",
        "parameter11": "",
        "osRequirements": "",
        "scriptContents": $escapedContent
    }
	EOF

    echo "Uploaded $key from $localPath to Jamf"
}

updateJamf() {
    local key="$1"
    local scriptID="${jamfInventory[$key]}"
    local localPath="${localInventory[$key]}"

    if [[ -z "$scriptID" ]]; then
        debug "Cannot update $key: Jamf ID not found"
        return 1
    fi

    if [[ ! -f "$localPath" ]]; then
        debug "Cannot update $key: Local file not found at $localPath"
        return 1
    fi

    local localScriptContent
    localScriptContent=$(cat "$localPath")
    localScriptContent=$(normalizeContent "$localScriptContent")

    local escapedContent
    escapedContent=$(jq -Rs '.' <<< "$localScriptContent")

    if [[ "$debugMode" == "true" ]]; then
        debug "Would have updated Jamf script '$key' (ID: $scriptID) from $localPath"
        return 0
    fi

    curl -s -X PUT "$scriptURL/$scriptID" \
        -H "Authorization: Bearer ${bearerToken}" \
        -H "Content-Type: application/json" \
        -d @- <<-EOF
    {
        "name": "$key",
        "info": "",
        "notes": "",
        "priority": "AFTER",
        "categoryId": "1",
        "parameter4": "",
        "parameter5": "",
        "parameter6": "",
        "parameter7": "",
        "parameter8": "",
        "parameter9": "",
        "parameter10": "",
        "parameter11": "",
        "osRequirements": "",
        "scriptContents": $escapedContent
    }
	EOF

    echo "Updated Jamf script '$key' (ID: $scriptID) from $localPath"
}

retrieveLocalScriptContent() {
    local key="$1"
    local localScriptPath="$WORKING_DIRECTORY/$key.sh"

    if [[ ! -f "$localScriptPath" ]]; then
        debug "Local script not found for key: $key"
        localScriptContent=""
        return 1
    fi

    localScriptContent=$(<"$localScriptPath")
    localScriptContent=$(normalizeContent "$localScriptContent")
}

retrieveJamfScriptContent() {
    local key="$1"
    local script_ID="${jamfInventory[$key]:-}"

    if [[ -z "$script_ID" ]]; then
        debug "WARN: No Jamf ID found for key '$key'"
        jamfScriptContent=""
        return 1
    fi

    jamfScriptContent=$(echo "$jamfScriptBuild" | \
        jq -r --arg id "$script_ID" '.results[] | select(.id | tostring == $id) | .scriptContents // empty')

    jamfScriptContent=$(normalizeContent "$jamfScriptContent")

    scriptID="$script_ID"
}

getBearerToken
buildLocalInventory
buildJamfInventory
compareInventories
invalidateToken

endTime=$(date +%s)
timeDiff=$(($endTime - $startTime))
echo "Total time: $timeDiff seconds"
