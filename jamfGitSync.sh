#!/bin/bash

## Create by Trenton Cook
## Created on 2025-12-22
## Version 1.3 - 2025-12-27

debugMode="false"

## Logging / Debugging
debug() {
    if [[ "$debugMode" == "true" ]]; then
        echo "DEBUG: $@"
    fi
}

error() {
    echo "ERROR: $@"
    exit 1
}

warn() {
    echo "WARNING: $@"
}

## FUNCTIONS
preflight() {
    if [[ ! -d "$WORKING_DIRECTORY" ]]; then
        warn "Working directory ($WORKING_DIRECTORY) does not exist"
		mkdir "$WORKING_DIRECTORY"
    fi

    if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$JAMF_URL" ]]; then
        error "Missing required credentials, are all your GitHub secrets set?"
    fi

    scriptURL="$JAMF_URL/api/v1/scripts"
    startTime=$(date +%s)
}

normalize() {
    local mode="$1"
    local content="$2"

    case "$mode" in
        "content")
            echo "$content" | tr -d '\r' | sed 's\[[:space:]]*$//' | sed -e :a -e '/^\s*$/d;N;ba'
        ;;
        "json")
            echo "$content" | jq -c 'del(.scriptContents, .id)'
        ;;
        "jsonMetadata")
            echo "$content" | jq 'del(.scriptContents)'
        ;;
        "name")
            echo "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\r' | tr -d '\000' | sed 's/[[:space:]]\+/ /g' | tr '[:upper:]' '[:lower:]'
        ;;
    esac
}

getToken() {
    local resp

    resp=$(curl -s --location --request POST "$JAMF_URL/api/oauth/token" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "client_secret=$CLIENT_SECRET" \
    --data-urlencode "grant_type=client_credentials" \
    )

    token=$(echo $resp | jq -r '.access_token // empty')

    if [[ -z "$token" ]]; then
        error "Bearer token could not be retrieved"
    else
        debug "Bearer token retrieved successfully"
    fi
}

yeetToken() {
    local resp

    resp=$(curl -w "%{http_code}" -H "Authorization: Bearer ${token}" $JAMF_URL/api/v1/auth/invalidate-token -X POST -s -o /dev/null)

    if [[ ${resp} != 204 ]]; then
        warn "Bearer token could not be invalidated"
    else
        debug "Bearer token invalidated successfully"
    fi

    token=""
}

parseAllJamfScripts() {
    parseStart=$(date +%s)
    if [[ "$parsedAlready" == "true" ]]; then
        return
    fi
    parsedAlready="true"
    local jsonResponse="$1"
    declare -gA jamfInventory
    declare -gA jamfMetadata
    
    # Parse each script
    local resultsCount
    resultsCount=$(echo "$jsonResponse" | jq '.results | length')

    if [[ -z "$(ls -A "$WORKING_DIRECTORY" 2>/dev/null)" ]]; then
        newBuild="true"
    fi
    
    for ((i=0; i<resultsCount; i++)); do
        local script
        script=$(echo "$jsonResponse" | jq -r ".results[$i]")
        
        id=$(echo "$script" | jq -r '.id // ""')
        name=$(echo "$script" | jq -r '.name // ""')
        info=$(echo "$script" | jq -r '.info // ""')
        notes=$(echo "$script" | jq -r '.notes // ""')
        priority=$(echo "$script" | jq -r '.priority // "AFTER"')
        
        param4=$(echo "$script" | jq -r '.parameter4 // ""')
        param5=$(echo "$script" | jq -r '.parameter5 // ""')
        param6=$(echo "$script" | jq -r '.parameter6 // ""')
        param7=$(echo "$script" | jq -r '.parameter7 // ""')
        param8=$(echo "$script" | jq -r '.parameter8 // ""')
        param9=$(echo "$script" | jq -r '.parameter9 // ""')
        param10=$(echo "$script" | jq -r '.parameter10 // ""')
        param11=$(echo "$script" | jq -r '.parameter11 // ""')
        
        osRequirements=$(echo "$script" | jq -r '.osRequirements // ""')
        scriptContents=$(echo "$script" | jq -r '.scriptContents // ""')
        categoryId=$(echo "$script" | jq -r '.categoryId // "1"')
        categoryName=$(echo "$script" | jq -r '.categoryName // ""')
        
        if [[ "$newBuild" == "true" ]]; then
            buildLocalFile
        fi
            jamfInventory["$name"]="$scriptContents"

            jamfMetadata["$name"]=$(jq -n \
                --arg id "$id" \
                --arg name "$name" \
                --arg info "$info" \
                --arg notes "$notes" \
                --arg priority "$priority" \
                --arg param4 "$param4" \
                --arg param5 "$param5" \
                --arg param6 "$param6" \
                --arg param7 "$param7" \
                --arg param8 "$param8" \
                --arg param9 "$param9" \
                --arg param10 "$param10" \
                --arg param11 "$param11" \
                --arg osRequirements "$osRequirements" \
                --arg scriptContents "$scriptContents" \
                --arg categoryId "$categoryId" \
                --arg categoryName "$categoryName" \
                '{
                    id: $id,
                    name: $name,
                    info: $info,
                    notes: $notes,
                    priority: $priority,
                    parameter4: $param4,
                    parameter5: $param5,
                    parameter6: $param6,
                    parameter7: $param7,
                    parameter8: $param8,
                    parameter9: $param9,
                    parameter10: $param10,
                    parameter11: $param11,
                    osRequirements: $osRequirements,
                    scriptContents: $scriptContents,
                    categoryId: $categoryId,
                    categoryName: $categoryName
                }'
            )
    done

    debug "Parsed $resultsCount Jamf scripts in $(($(date +%s) - parseStart)) seconds"
    newBuild="false"
}

buildLocalFile() {
    ## Check for folder
    if [[ ! -d "$WORKING_DIRECTORY/$name" ]]; then
        mkdir "$WORKING_DIRECTORY/$name"
    fi

    ## Create metadata file
    jq -n \
        --arg id "$id" \
        --arg name "$name" \
        --arg info "$info" \
        --arg notes "$notes" \
        --arg priority "$priority" \
        --arg param4 "$param4" \
        --arg param5 "$param5" \
        --arg param6 "$param6" \
        --arg param7 "$param7" \
        --arg param8 "$param8" \
        --arg param9 "$param9" \
        --arg param10 "$param10" \
        --arg param11 "$param11" \
        --arg osRequirements "$osRequirements" \
        --arg categoryId "$categoryId" \
        --arg categoryName "$categoryName" \
        '{
            id: $id,
            name: $name,
            info: $info,
            notes: $notes,
            priority: $priority,
            parameter4: $param4,
            parameter5: $param5,
            parameter6: $param6,
            parameter7: $param7,
            parameter8: $param8,
            parameter9: $param9,
            parameter10: $param10,
            parameter11: $param11,
            osRequirements: $osRequirements,
            categoryId: $categoryId,
            categoryName: $categoryName
        }' > "$WORKING_DIRECTORY/$name/metadata.json"

    ## Create content file
    echo "$scriptContents" > "$WORKING_DIRECTORY/$name/$name.sh"
}

compareInventories() {
    declare -gA localInventory
    declare -gA localMetadata
    toChange=""
    toUpload=""
    toDownload=""

    while IFS= read -r script; do
        base="${script##*/}"
        scriptName="${base%.sh}"

        content=$(cat "$WORKING_DIRECTORY/${scriptName}/$base")

        localInventory[${scriptName}]="$content"
    done < <(
        find "$WORKING_DIRECTORY" -mindepth 2 -maxdepth 2 -type f -name "*.sh"
    )

    while IFS= read -r metadataFile; do
        dirName="$(basename "$(dirname "$metadataFile")")"

        content=$(<"$metadataFile")

        localMetadata["$dirName"]="$content"
    done < <(
        find "$WORKING_DIRECTORY" -mindepth 2 -maxdepth 2 -type f -name "metadata.json"
    )

    parseAllJamfScripts "$jamfScriptObject"

    for script in "${!jamfInventory[@]}"; do
        if [[ -v localInventory[$script] ]] || [[ -v localMetadata[$script] ]]; then
            local localMeta=$(normalize "json" "${localMetadata[$script]}")
            local jamfMeta=$(normalize "json" "${jamfMetadata[$script]}")
            if [[ "${localInventory[$script]}" != "${jamfInventory[$script]}" ]] || [[ "$localMeta" != "$jamfMeta" ]]; then
                debug "Script $script has changed"
                toChange+=("-- $script\n")
                toChangeReal+=("$script")
            fi
        else
            debug "Script $script does not exist in local"
            toDownload+=("-- $script\n")
            toDownloadReal+=("$script")
        fi
    done

    if [[ -n "${toChange[@]}" ]]; then
        echo -e "Scripts to update: \n${toChange[@]}"
    fi

    for script in "${!localInventory[@]}"; do
        if [[ ! -v jamfInventory[$script] ]]; then
            debug "Script $script does not exist in Jamf"
            toUpload+=("-- $script\n")
            toUploadReal+=("$script")
        fi
    done

    if [[ -n "${toUpload[@]}" ]]; then
        echo -e "Scripts to upload: \n${toUpload[@]}"
    fi

    if [[ -n "${toDownload[@]}" ]]; then
        echo -e "Scripts to download: \n${toDownload[@]}"
    fi
}

applyChanges() {
    if [[ ${#toChangeReal[@]} != 0 ]]; then
        for script in "${toChangeReal[@]}"; do
            local scriptID="$(echo ${jamfMetadata[$script]} | jq -r '.id // ""')"
            local localPath="$WORKING_DIRECTORY/$script/$script.sh"
            local scriptContent="$(cat "$localPath")"
            local escapedContent=$(jq -Rs '.' <<< "$scriptContent")
            
            local meta="$(cat "$WORKING_DIRECTORY/$script/metadata.json")"
            local info=$(echo "$meta" | jq -r '.info // ""')
            local notes=$(echo "$meta" | jq -r '.notes // ""')
            local priority=$(echo "$meta" | jq -r '.priority // "AFTER"')
            local param4=$(echo "$meta" | jq -r '.parameter4 // ""')
            local param5=$(echo "$meta" | jq -r '.parameter5 // ""')
            local param6=$(echo "$meta" | jq -r '.parameter6 // ""')
            local param7=$(echo "$meta" | jq -r '.parameter7 // ""')
            local param8=$(echo "$meta" | jq -r '.parameter8 // ""')
            local param9=$(echo "$meta" | jq -r '.parameter9 // ""')
            local param10=$(echo "$meta" | jq -r '.parameter10 // ""')
            local param11=$(echo "$meta" | jq -r '.parameter11 // ""')
            local osRequirements=$(echo "$meta" | jq -r '.osRequirements // ""')
            local categoryId=$(echo "$meta" | jq -r '.categoryId // "1"')
            local categoryName=$(echo "$meta" | jq -r '.categoryName // ""')

            curl -s -X PUT "$scriptURL/$scriptID" \
                -H "Authorization: Bearer ${token}" \
                -H "Content-Type: application/json" \
                -d @-<<-EOF >/dev/null 2>&1
            {
                "name": "$script",
                "info": "$info",
                "notes": "$notes",
                "priority": "$priority",
                "categoryId": "$categoryId",
                "parameter4": "$param4",
                "parameter5": "$param5",
                "parameter6": "$param6",
                "parameter7": "$param7",
                "parameter8": "$param8",
                "parameter9": "$param9",
                "parameter10": "$param10",
                "parameter11": "$param11",
                "osRequirements": "$osRequirements",
                "scriptContents": $escapedContent
            }
	EOF
        done
    fi

    if [[ ${#toDownloadReal[@]} != 0 ]]; then
        for script in "${toDownloadReal[@]}"; do
            local scriptContent=$(echo "${jamfInventory[$script]}")
            local metaContent=$(echo "${jamfMetadata[$script]}")
            metaContent=$(normalize "jsonMetadata" "$metaContent")
            local filePath="$WORKING_DIRECTORY/$script/$script.sh"
            local directoryPath="$WORKING_DIRECTORY/$script"
            local metadataPath="$WORKING_DIRECTORY/$script/metadata.json"

            if [[ ! -d "$directoryPath" ]]; then
                mkdir "$directoryPath"
            fi

            echo "$scriptContent" > "$filePath"
            echo "$metaContent" > "$metadataPath"
        done
    fi

    if [[ ${#toUploadReal[@]} != 0 ]]; then
        for script in "${toUploadReal[@]}"; do
            local scriptContent=$(echo "${localInventory[$script]}")
            local metaContent=$(echo "${localMetadata[$script]}")
            local escapedContent=$(jq -Rs '.' <<< "$scriptContent")

            local info=$(echo "$metaContent" | jq -r '.info // ""')
            local notes=$(echo "$metaContent" | jq -r '.notes // ""')
            local priority=$(echo "$metaContent" | jq -r '.priority // "AFTER"')
            local param4=$(echo "$metaContent" | jq -r '.parameter4 // ""')
            local param5=$(echo "$metaContent" | jq -r '.parameter5 // ""')
            local param6=$(echo "$metaContent" | jq -r '.parameter6 // ""')
            local param7=$(echo "$metaContent" | jq -r '.parameter7 // ""')
            local param8=$(echo "$metaContent" | jq -r '.parameter8 // ""')
            local param9=$(echo "$metaContent" | jq -r '.parameter9 // ""')
            local param10=$(echo "$metaContent" | jq -r '.parameter10 // ""')
            local param11=$(echo "$metaContent" | jq -r '.parameter11 // ""')
            local osRequirements=$(echo "$metaContent" | jq -r '.osRequirements // ""')
            local categoryId=$(echo "$metaContent" | jq -r '.categoryId // "1"')
            local categoryName=$(echo "$metaContent" | jq -r '.categoryName // ""')
            
            if [[ -z "$scriptContent" ]]; then
                warn "Content for $script is empty, did you mean to upload this?"
            fi

            if [[ -z "$metaContent" ]]; then
                warn "Metadata for $script is empty, did you mean to upload this?"
            fi

            resp=$(curl -s -X POST "$scriptURL" \
                -H "Authorization: Bearer ${token}" \
                -H "Content-Type: application/json" \
                -d @- <<-EOF
            {
                "name": "$script",
                "info": "$info",
                "notes": "$notes",
                "priority": "$priority",
                "categoryId": "$categoryId",
                "parameter4": "$param4",
                "parameter5": "$param5",
                "parameter6": "$param6",
                "parameter7": "$param7",
                "parameter8": "$param8",
                "parameter9": "$param9",
                "parameter10": "$param10",
                "parameter11": "$param11",
                "osRequirements": "$osRequirements",
                "scriptContents": $escapedContent
            }
	EOF
            )

            local scriptID=$(echo "$resp" | jq -r '.id // ""')
            local tempFile="$WORKING_DIRECTORY/$script/metadataTemp.json"
            local metadataPath="$WORKING_DIRECTORY/$script/metadata.json"
            jq --arg id "$scriptID" '.id = $id' "$metadataPath" > "$tempFile"
            mv "$tempFile" "$metadataPath"
        done
    fi
}

## Main Runtime
preflight
getToken
jamfScriptObject=$(curl -s -H "Authorization: Bearer ${token}" "$scriptURL?page=0&page-size=2000")
if [[ -z "$(ls -A "$WORKING_DIRECTORY" 2>/dev/null)" ]]; then
    parseAllJamfScripts "$jamfScriptObject"
else
    debug "Local scripts already exist"
fi
compareInventories
if [[ ( ${#toDownload[@]} != 1 || ${#toUpload[@]} != 1 || ${#toChange[@]} != 1 ) && "$debugMode" == "false" ]]; then
    echo "Applying queued changes"
    if [[ "$debugMode" == "true" ]]; then
        debug "Would have applied queued changes"
    else
        applyChanges
    fi
else
    echo "No changes to apply, cleaning up..."
fi
yeetToken

echo "Completed in $(( $(date +%s) - $startTime )) seconds"
