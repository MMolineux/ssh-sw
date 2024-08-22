#!/usr/bin/env bash
VERSION="2.0.0"
SSH_CONFIG_PATH=~/.ssh/config
SSH_PROFILE_PATH=~/.ssh/profiles

if ! [ -d "${SSH_PROFILE_PATH}" ]; then
    echo "profiles directory didn't exist. creating ${SSH_PROFILE_PATH}"
    mkdir -p "${SSH_PROFILE_PATH}"
fi

function show_usage () {
echo -e "
Usage: $(basename $0) [-hvrle] [-c profile_name] [-d profile_name] [host]

Description:
    Switch between and manage vanilla ssh config profiles, then easily connect to ssh hosts via a cli interface.
    
Options:
    -h|--help       Display this help message.
    -v|--version    Display version infomation.
    -b|--back {n}   Reconnect to last ssh host or select specific host from history (zero-indexed).
    -r|--reload     After editing a profile manually. Reload profile into ssh config.
    -l|--list       List available profiles and show current profile's hosts.
    -e|--edit       Edit currently active profile.
    -c|--create     Create a new empty profile with the provided profile_namep
    -d|--delete     Delete a profile by name.

Behaviour:
    Without arguments $(basename $0) is interactive, providing a user friendly cli to select a profile and then connect to an ssh host.
"
}

#Track whether user switcheprofile
show_interactive=true

# Usage: options=("one" "two" "three"); inputChoice "Choose:" 1 "${options[@]}"; choice=$?; echo "${options[$choice]}"
function inputChoice() {
    echo "${1}"; shift
    echo "$(tput dim)""- Change option: [up/down], Select: [ENTER]" "$(tput sgr0)"
    local selected="${1}"; shift

    ESC=$(echo -e "\033")
    cursor_blink_on()  { tput cnorm; }
    cursor_blink_off() { tput civis; }
    cursor_to()        { tput cup $(($1-1)); }
    print_option()     { echo "$(tput sgr0)" "$1" "$(tput sgr0)"; }
    print_selected()   { echo "$(tput rev)" "$1" "$(tput sgr0)"; }
    get_cursor_row()   { IFS=';' read -rsdR -p $'\E[6n' ROW COL; echo "${ROW#*[}"; }
    key_input()        { read -rs -n3 key 2>/dev/null >&2; [[ $key = ${ESC}[A ]] && echo up; [[ $key = ${ESC}[B ]] && echo down; [[ $key = "" ]] && echo enter; }

    for opt; do echo; done

    local lastrow
    lastrow=$(get_cursor_row)
    local startrow=$((lastrow - $#))
    trap "cursor_blink_on; echo; echo; exit" 2
    cursor_blink_off

    : selected:=0

    while true; do
        local idx=0
        for opt; do
            cursor_to $((startrow + idx))
            if [ ${idx} -eq "${selected}" ]; then
                print_selected "${opt}"
            else
                print_option "${opt}"
            fi
            ((idx++))
        done

        case $(key_input) in
            enter) break;;
            up)    ((selected--)); [ "${selected}" -lt 0 ] && selected=$(($# - 1));;
            down)  ((selected++)); [ "${selected}" -ge $# ] && selected=0;;
        esac
    done

    cursor_to "${lastrow}"
    cursor_blink_on
    echo

    return "${selected}"
}

function show_hosts() {
    echo "Hosts in current profile:"
    cat $SSH_CONFIG_PATH | grep -Po "(?<=Host )[^*].*[^*]$" | nl #exclude full wildcard
}

function show_profiles() {
    current_name=$(get_profile_name $SSH_CONFIG_PATH)

    echo "Available profiles:"
    if [[ -n "${current_name}" ]]; then    
        ls -1 $SSH_PROFILE_PATH | nl | sed "s/$current_name/$current_name - active/g"
    else
        ls -1 $SSH_PROFILE_PATH | nl
    fi
}

#Usage: get_profile_name path - Check file at profile_path for presence of valid header and name
function get_profile_name() {
    profile_path=$1
    if [[ "$(sed -n '1p' "$profile_path")" == *"###PROFILE_NAME###"* ]]; then
        profile_name=$(sed -n '2p' $profile_path)
        if [[ -n "$profile_name" ]]; then
            profile_name=$(echo $profile_name | tr -d \# )
            echo $profile_name
        fi
        
    fi
}

function set_profile_name() {
    profile_path=$1
    profile_name=$(get_profile_name $profile_path)

    #if not empty, ensure header is there.
    if [ -s "$profile_path" ]; then
        if [[ -n "$profile_name" ]]; then
            #does profile name in file match file path
            if [[ "$profile_name" != "$(basename "$profile_path")" ]]; then
                sed -i "2i #$(basename "$profile_path")" "$profile_path"
            fi
        else
            sed -i "1i ###PROFILE_NAME###\n#$(basename "$profile_path")" "$profile_path"
        fi
    else
        echo "Warning: You're switching to an empty config profile. Use --edit to configure the profile"
        echo -e "###PROFILE_NAME###\n#$(basename "$profile_path")" > "$profile_path"
    fi
}

function backup_config() {
    cp $SSH_CONFIG_PATH /tmp/ssh_config.bak
}

#Usage: switch_profile new_profile
function switch_profile() {
    new_profile=$1
    backup_config
    new_profile_path=$SSH_PROFILE_PATH/$new_profile

    set_profile_name "$new_profile_path"    
    cp "$new_profile_path" $SSH_CONFIG_PATH   
}

function reload_profile() {
    current=$(get_profile_name $SSH_CONFIG_PATH)
    switch_profile "$current"
}

function edit_current_profile() {
    current=$(get_profile_name $SSH_CONFIG_PATH)
    
    if [[ -n "$EDITOR" ]]; then
        $EDITOR "$SSH_PROFILE_PATH/$current"
    else
        if ! xdg-open "$SSH_PROFILE_PATH/$current" 2> /dev/null; then
            echo "Failed to open a text editor to edit your profile."
            echo "Please export \$EDITOR to your env."
            echo "e.g. add \"export EDTIOR=/usr/bin/nano\" to the bottom of your ~/.bashrc"
        fi
    fi
    
    switch_profile "$current"
}


function delete_profile() {
    local profile_path="$SSH_PROFILE_PATH/$1"
    if [ -f "$profile_path" ]; then
        read -p "Are you sure you want to delete $1?" answer
        case "${answer}" in
            Y|y|Yes*|yes*)
                
                    echo "Ok, deleting $1..."
                    rm "$profile_path"
                    if (( $? == 0 )); then
                        echo "Done"
                        # switch back to index 0
                        profiles=($(ls -1 $SSH_PROFILE_PATH))
                        switch_back_profile="${profiles[0]}"
                        if [ -n "$switch_back_profile" ]; then
                            echo "Switching back to first profile: $switch_back_profile"
                            switch_profile "$switch_back_profile"
                        else
                            # clear contents of active profile and rename
                            sed -i '2s/.*/#main/;3,$d' "$SSH_CONFIG_PATH"
                        fi
                    else
                        echo "Failed to delete $profile_path" >&2
                        exit 1
                    fi
                    
                
            ;;
            *)
                echo "Ok, didn't delete profile $1."
                exit 0
            ;;
        esac
    else
        echo "No profile by name $1" >&2
        exit 1
    fi
}

function interactive_profile_select () {
    profiles=($(ls -1 $SSH_PROFILE_PATH))
    current=$(get_profile_name $SSH_CONFIG_PATH)
    idx_current=0
    input_prompt="Select a profile:"

    if [[ -n "${current}" ]]; then

        for i in "${!profiles[@]}"; do
            if [[ "${profiles[$i]}" == "${current}" ]]; then
                break
            fi
            idx_current=$((idx_current +1))
        done

        input_prompt="$current is active, select a profile:"

    fi

inputChoice "$input_prompt" $idx_current "${profiles[@]}"; choice=$?

switch_profile "${profiles[$choice]}"
}

function interactive_host_select (){ 
    hosts=($(cat $SSH_CONFIG_PATH | grep -Po "(?<=Host )[^*].*[^*]$" | sed -z 's/\n/\t/g'))
    inputChoice "Select an ssh host to connect to:" 0 "${hosts[@]}"; choice=$?
    
    # store host in env
    if [[ -f "${SSHSW_HISTORY_FILE}" ]]; then 
        history_str=$(cat "${SSHSW_HISTORY_FILE}")
        echo "${hosts[$choice]},${history_str}" > "${SSHSW_HISTORY_FILE}"
    else
        echo "${hosts[$choice]}" > "${SSHSW_HISTORY_FILE}"
    fi
    ssh "${hosts[$choice]}"
}

function connect_prev_profile() {
    n="$1" 
    # zero indexed
    n=$(( $1 + 1 ))
    if [[ -f "${SSHSW_HISTORY_FILE}" ]]; then
        history_str=$(cat "${SSHSW_HISTORY_FILE}")
        
        # count items in history
        history_count=$(echo "$history_str" | tr -cd "," | wc -c)
        history_count=$(($history_count + 1))
        if [[ $history_count -lt $n ]]; then
            echo "Request $n host(s) ago. History only has $history_count hosts"
            exit 1
        fi
        
        host=$(cat "${SSHSW_HISTORY_FILE}" | awk -F',' '{print $'$n'}')
        echo "Connecting to $host"
        ssh "${host}"
    else
        echo "No previous hosts"
        exit 0
    fi
}

function create_new_profile() {
    local new_profile_path="$SSH_PROFILE_PATH/$1"
    if [ -f "$new_profile_path" ]; then
        echo "A profile named $1 already exists." >&2
        exit 1
    else
        touch "$new_profile_path"
        switch_profile "$1"
        edit_current_profile
    fi
}


if ! [ -f "$SSH_CONFIG_PATH" ]; then
    echo "Warning: $SSH_CONFIG_PATH didn't exist. Creating example config file now."
    # create empty profile with name "example"
echo "###PROFILE_NAME###
#example

Host example-deleteme
    Hostname example.com
    User admin
    IdentityFile ~/.ssh/id_rsa" | tee "$SSH_CONFIG_PATH" > "$SSH_PROFILE_PATH/example"

echo ""
echo "Now use the -e flag to edit the example config file, or -c flag to create a new one"
exit 0
fi

export SSHSW_HISTORY_FILE="/tmp/sshsw_history_$(get_profile_name $SSH_CONFIG_PATH)"


POSITIONAL=()
while (( $# > 0 )); do
    case "${1}" in
        #Help message
        -h|--help)
            show_usage
            shift
            show_interactive=false
        ;;
        -v|--version)
            echo "Version: $VERSION"
            shift
            show_interactive=false
        ;;
        #Create a new profile
        -c|--create)
            numOfArgs=1 # number of switch arguments
            if (( $# < numOfArgs + 1 )); then
                echo "Missing profile name for --create." >&2
                echo "See $(basename $0) --help for usage info."
                exit 1
            else
                create_new_profile "${2}"
                shift $((numOfArgs + 1)) # shift 'numOfArgs + 1' to bypass switch and its value
            fi
            exit 0
        ;;
        #Delete a profile
        -d|--delete)
            numOfArgs=1
            if (( $# < numOfArgs +1 )); then
                echo "Missing profile name for --delete." >&2
                echo "See $(basename $0) --help for usage info."
                exit 1
            else
                delete_profile "${2}"
            fi
            exit 0
        ;;
        -b|--back)
            numOfArgs=1
            if (( $# < 2 )); then
                connect_prev_profile 0
            else
                if [[ "${2}" =~ [lc] ]]; then
                    if [ -f "${SSHSW_HISTORY_FILE}" ]; then

                        cat "${SSHSW_HISTORY_FILE}" | sed -z "s/,/\n/g"
                        if [ "${2}" == 'c' ]; then 
                            echo "Clearing history"
                            rm "${SSHSW_HISTORY_FILE}"
                        fi
                    else
                        echo "No history to list"
                        exit 0
                    fi
                else
                    connect_prev_profile "${2}"
                fi
            fi
            exit 0
        ;;
        -r|--reload)
            reload_profile
            exit 0
        ;;
        -e|--edit)
            edit_current_profile
            show_interactive=false
            shift
        ;;
        -l|--list)
            show_profiles
            show_hosts
            show_interactive=false
            shift
        ;;
        #unknown flag/switch
        -*) 
            echo "Unknown option ${1}." >&2
            echo "See $(basename $0) --help for usage info"
            exit 1
        ;;
         # positional
        *)
            POSITIONAL+=("${1}")
            shift
        ;;
    esac
done

set -- "${POSITIONAL[@]}" # restore positional params


if [ ${#POSITIONAL[@]} == 0 ]; then
    if $show_interactive; then
        #Interactive selection
        interactive_profile_select
        interactive_host_select
    fi
else
    profile=$1
    if [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
        profiles=(`ls -1 $SSH_PROFILE_PATH`)
        profile="${profiles[$1-1]}"
        if [[ -z "$profile" ]]; then
            echo "Error: $1 is not a valid profile number."
            exit 1
        fi
    else
            echo "Error: $1 is not a valid profile number."
            exit 1
    fi
    
    if [ -f "$SSH_PROFILE_PATH/$profile" ]; then
        switch_profile $profile
    else
        echo "Error: Profile \"$profile\" doesn't exist. Use --create to add a new profile." >&2
        exit 1
    fi
fi
