CONFIG_FILE="config.ini"
ENABLE_DEBUG_OUTPUT=false  # Set this to false to disable debug output

# Helper function to generate variable names from section and variable names
generate_variable_name() {
    local section="$1"
    local variable="$2"
    if [ "$section" = "DEFAULT" ]; then
        echo "${variable^^}"
    else
        echo "${section^^}_${variable^^}"
    fi
}


# Loop through sections and variables in the config file and create variables
create_config_variables() {
    local config_file="$1"
    local section=""
    while IFS= read -r line; do
        # echo "$line"
        if [[ $line =~ ^\[(.*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^([A-Za-z_][A-Za-z_0-9]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local variable="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            local exported_variable_name="$(generate_variable_name "$section" "$variable")"
            if [ "$ENABLE_DEBUG_OUTPUT" = true ]; then
                echo "$exported_variable_name=$value"
            fi
            eval "$exported_variable_name=$value"
        fi
    done < "$config_file"
}

# Call create_config_variables to create variables from the config file
if [ "$ENABLE_DEBUG_OUTPUT" = true ]; then
    echo "Parsing configuration file: $CONFIG_FILE"
fi
create_config_variables "$CONFIG_FILE"