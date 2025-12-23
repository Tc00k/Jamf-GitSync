#!/bin/bash

## Created by Trenton Cook
## Mass updates scripts in your Jamf Pro instance to match your locally hosted Git repository

###############
## VARIABLES ##
###############

## When set to 'true' this will disable the uploadToJamf function for testing purposes
debugMode="false"

## DO NOT CHANGE
scriptURL="$JAMF_URL/api/v1/scripts"
startTime=$(date +%s)

###############
## FUNCTIONS ##
###############

## Bearer token retrieval function
getBearerToken() {
    local responseBody
    responseBody=$(curl -s --location --request POST "$JAMF_URL/api/oauth/token" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=$JAMF_CLIENT_ID" \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "client_secret=$JAMF_CLIENT_SECRET" \
    )

    bearerToken=$(echo $responseBody | jq -r '.access_token // empty')

    if [[ -z "$bearerToken" ]]; then
        echo "FAILURE: Bearer token could not be retrieved"
        exit 1
    fi
}

## Bearer token invalidation function
invalidateToken() {
    local responseBody

    responseBody=$(curl -w "%{http_code}" -H "Authorization: Bearer ${bearerToken}" $JAMF_URL/api/v1/auth/invalidate-token -X POST -s -o /dev/null)

    if [[ ${responseBody} != 204 ]]; then
        echo "FAILURE: Bearer token could not be invalidated"
        return 1
    fi

    bearerToken=""
}

## Retrieve local script contents function
retrieveLocalScriptContent() {
    local localScriptPath="$WORKING_DIRECTORY/$1.sh"

    if [[ ! -f "$localScriptPath" ]]; then
        echo "Script $1 not found in working directory"
        return
    fi

    localScriptContent=$(cat "$localScriptPath")
    localScriptContent=$(echo "$localScriptContent" | tr -d '\r' | sed 's/[[:space:]]*$//')
}

## Retrieve Jamf script contents function
retrieveJamfScriptContent() {
    local scriptName=$1
    local script_ID="${2:-}"
    local combinations=("$scriptName" "${scriptName// /_}" "${scriptName//_/ }")
    local totalCount
    local retrievedCount

    if [[ -z "$script_ID" ]]; then
        while true; do
            for nameVariant in "${combinations[@]}"; do
                script_ID=$( echo "$scriptResponse" | jq -r --arg script_name "$nameVariant" '.results[] | select(.name == $script_name) | .id')
                if [[ -n "$script_ID" ]]; then
                    break 2
                fi
            done

            totalCount=$( echo "$scriptResponse" | jq -r '.totalCount' )
            retrievedCount=$( echo "$scriptResponse" | jq -r '.results | length' )
            if [[ $retrievedCount -ge $totalCount ]]; then
                break
            fi
        done
    fi

    if [[ -z "$script_ID" ]]; then
        echo "WARN: '$scriptName' not found in Jamf, skipping"
        return 1
    fi

    jamfScriptObject=$( curl -s -X 'GET' "$scriptURL/$script_ID" -H 'accept: application/json' -H "Authorization: Bearer $bearerToken" )

    ## Extract all values and assign to individual variables
    name=$(echo "$jamfScriptObject" | jq -r '.name')
    info=$(echo "$jamfScriptObject" | jq -r '.info')
    notes=$(echo "$jamfScriptObject" | jq -r '.notes')
    priority=$(echo "$jamfScriptObject" | jq -r '.priority')
    categoryId=$(echo "$jamfScriptObject" | jq -r '.categoryId')
    parameter4=$(echo "$jamfScriptObject" | jq -r '.parameter4')
    parameter5=$(echo "$jamfScriptObject" | jq -r '.parameter5')
    parameter6=$(echo "$jamfScriptObject" | jq -r '.parameter6')
    parameter7=$(echo "$jamfScriptObject" | jq -r '.parameter7')
    parameter8=$(echo "$jamfScriptObject" | jq -r '.parameter8')
    parameter9=$(echo "$jamfScriptObject" | jq -r '.parameter9')
    parameter10=$(echo "$jamfScriptObject" | jq -r '.parameter10')
    parameter11=$(echo "$jamfScriptObject" | jq -r '.parameter11')
    osRequirements=$(echo "$jamfScriptObject" | jq -r '.osRequirements')
    jamfScriptContent=$(echo "$jamfScriptObject" | jq -r '.scriptContents' | tr -d '\r' | sed 's/[[:space:]]*$//')

    scriptID="$script_ID"
}

## Push updates to Jamf scripts function
updateScript() {
    local scriptNameTotal="$1"
    local scriptID="$2"
    local escapedLocalScriptContent

    retrieveJamfScriptContent "$scriptNameTotal" "$scriptID"
    retrieveLocalScriptContent "$scriptNameTotal"

    escapedLocalScriptContent=$(jq -Rs '.' <<<"$localScriptContent")

    if [[ "$debugMode" == "true" ]]; then
        echo "Script $scriptNameTotal would be updated"
    else
        curl -s -o /dev/null -X 'PUT' \
            "${scriptURL}/${scriptID}" \
            -H 'accept application/json' \
            -H "Authorization: Bearer $bearerToken" \
            -H "Content-Type: application/json" \
            -d @- <<-EOF
		{
		    "name": "$name",
		    "info": "$info",
		    "notes": "$notes",
		    "priority": "$priority",
		    "categoryId": "$categoryId",
		    "parameter4": "$parameter4",
		    "parameter5": "$parameter5",
		    "parameter6": "$parameter6",
		    "parameter7": "$parameter7",
		    "parameter8": "$parameter8",
		    "parameter9": "$parameter9",
		    "parameter10": "$parameter10",
		    "parameter11": "$parameter11",
		    "osRequirements": "$osRequirements",
		    "scriptContents": $escapedLocalScriptContent
		}
		EOF

        echo "Script $scriptNameTotal updated successfully"
    fi
}

WORKING_DIRECTORYCheck() {
    if [[ -d "${WORKING_DIRECTORY}" ]]; then
        echo "Working directory ${WORKING_DIRECTORY} exists"
        return 0
    fi

    echo "Working directory ${WORKING_DIRECTORY} does not exist"
    mkdir -p "$WORKING_DIRECTORY"
    if [[ $? -ne 0 ]]; then
        echo "Failed to create working directory ${WORKING_DIRECTORY}"
        exit 1
    fi
}

###############################
## CHECK FOR MISSING SCRIPTS ##
###############################

jamfScriptCount() {
    echo "$scriptResponse" | jq -r '.results[] | "\(.id)\t\(.name)"'
}

downloadMissing() {
    echo "Downloading any missing scripts from Jamf to local directory"

    jamfScriptCount | while IFS=$'\t' read -r scriptID scriptName; do
        [[ -z "${scriptID:-}" || -z "${scriptName:-}" ]] && continue

        local fileBase
        local outFile
        fileBase=$(echo "$scriptName" | sed -E 's/[[:space:]]+/_/g; s|/|_|g')
        outFile="${WORKING_DIRECTORY}/${fileBase}.sh"

        if [[ -f "$outFile" ]]; then
            continue
        fi

        echo "Downloading: ${scriptName}"

        local detail
        local body
        detail="$(curl -s -H "Authorization: Bearer ${bearerToken}" "${scriptURL}/${scriptID}")"
        body="$(echo "$detail" | jq -r '.scriptContents // .script_contents // .script // empty')"

        if [[ -z "$body" ]]; then
            echo "WARN: no script body returned for '${scriptName}' (ID: ${scriptID})" >&2
            continue
        fi

        scriptName="$(printf '%s' "$scriptName" | tr -d '\r\n')"
        printf "%s\n" "$body" > "$outFile"
    done
}

##################
## Main Runtime ##
##################

WORKING_DIRECTORYCheck
getBearerToken

changesFound="false"

## Gather all scripts from Jamf and their contents once
echo "Gathering all scripts from Jamf"
scriptResponse=$(curl -s -H "Authorization: Bearer ${bearerToken}" "$scriptURL?page=0&page-size=2000")

## Initialize associative array for change tracking
declare -A changedMap

## Iterate through all scripts in local directory and compare to their Jamf counterparts
echo "Comparing local scripts to Jamf counterparts"
echo ""
for script in "$WORKING_DIRECTORY"/*.sh; do
    echo "Comparing $(basename "$script")"
    scriptName=$(basename "$script" .sh)
    ## Gather local script content for comparison
    retrieveLocalScriptContent "$scriptName"
    ## Gather network script content for comparison
    retrieveJamfScriptContent "$scriptName"
    if [[ "$localScriptContent" != "$jamfScriptContent" ]]; then
        changedMap["$scriptName"]="$scriptID"
    fi
done
echo ""

## Output any changes found
if (( ${#changedMap[@]} > 0 )); then
    changesFound="true"
    echo "Changes found:"
    for name in "${!changedMap[@]}"; do
        echo "- $name"
    done
else
    echo "No changes found"
fi

## Update changed scripts in Jamf
if [[ "$changesFound" == "true" ]]; then
    getBearerToken
    for name in "${!changedMap[@]}"; do
        id="${changedMap[$name]}"
        updateScript "$name" "$id"
    done
fi

downloadMissing
invalidateToken

endTime=$(date +%s)
elapsedTime=$(( endTime - startTime ))
echo "Run took: $elapsedTime seconds"
