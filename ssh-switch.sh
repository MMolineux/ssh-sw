#!/usr/bin/env bash
VERSION="1.1.0"

SSH_CONFIG_PATH=~/.ssh/config
SSH_PROFILE_PATH=~/.ssh/profiles

function show_usage () {
echo \ "
Description:
    Script to handle switching between user config files for ssh. 

Usage: $(basename $0) [-hvire] [-c profile_name] [profile_name]

Options:
    -h|--help   Display this help message.
    -v|--version    Display version infomation.
    -i|--interactive    Displays list of ssh config profiles and prompts for numbered profile to switch to.
    -c|--create Interactively create a new profile with name supplied in \"profile_name\" opperand.
    -r|--reload After editing a profile under $SSH_PROFILE_PATH. Reload profile into ssh config.
    -e|--edit   Edit currently active profile.

Behaviour:
    Without arguments or options, $(basename $0) will list available ssh config profiles, highlighting the current profile with an asterisk (*).
    
    The ssh config profile will be switched to the given \"profile\" if known. 
"
}

#Track whether user switcheprofile
show_profiles=true

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

#Usage: get_profile_name path - Check file at profile_path for presence of valid header and name
function get_profile_name() {
    profile_path=$1
    if [[ "$(sed -n '1p' $profile_path)" == *"###PROFILE_NAME###"* ]]; then
        profile_name=$(sed -n '2p' $profile_path)
        if [[ -n "$profile_name" ]]; then
            profile_name=$(echo $profile_name | tr -d \# )
            echo $profile_name
        fi
        
    fi
}

function set_profile_name() {
    profile_path=$1
    profile_name=`get_profile_name $profile_path`

    #if not empty, ensure header is there.
    if [ -s "$profile_path" ]; then
        if [[ -n "$profile_name" ]]; then
            #does profile name in file match file path
            if [[ "$profile_name" != "$(basename $profile_path)" ]]; then
                sed -i "2i $(basename $profile_path)" $profile_path
            fi
        else
            sed -i "1i ###PROFILE_NAME###\n#$(basename $profile_path)" $profile_path
        fi
    else
        echo "Warning: You're switching to an empty config profile. Please configure $profile_path"
        echo -e "###PROFILE_NAME###\n#$(basename $profile_path)" > $profile_path
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

    set_profile_name $new_profile_path    
    cp $new_profile_path $SSH_CONFIG_PATH   
}

function reload_profile() {
    current=$(get_profile_name $SSH_CONFIG_PATH)
    switch_profile $current
}

function edit_current_profile() {
    current=$(get_profile_name $SSH_CONFIG_PATH)
    
    if [[ -n "$EDITOR" ]]; then
        $EDITOR $SSH_PROFILE_PATH/$current
    else
        xdg-open $SSH_PROFILE_PATH/$current
    fi
    
}

function interactive_selection () {
profiles=(`ls -1 $SSH_PROFILE_PATH`)
current=$(get_profile_name $SSH_CONFIG_PATH)
idx_current=0
input_prompt="Select a profile:"

if [[ -n "${current}" ]]; then

    for i in "${!profiles[@]}"; do
        if [[ "${profiles[$i]}" == "${current}" ]]; then
            break
        fi
        idx_current=$[idx_current +1]
    done

input_prompt="$current is active, select a profile:"

fi

inputChoice "$input_prompt" $idx_current "${profiles[@]}"; choice=$?

switch_profile "${profiles[$choice]}"
}

function create_new_profile() {
echo "Interactive profile creation coming soon....
Please edit $SSH_PROFILE_PATH/$1 manually for the time being."
exit 0
}


if ! [ -f "$SSH_CONFIG_PATH" ]; then
    echo "Warning: $SSH_CONFIG_PATH didn't exist. Creating blank config file now."
    touch $SSH_CONFIG_PATH
fi



POSITIONAL=()
while (( $# > 0 )); do
    case "${1}" in
        #Help message
        -h|--help)
        show_usage
        shift
        show_profiles=false
        ;;
        -v|--version)
        echo "Version: $VERSION"
        shift
        show_profiles=false
        ;;
        #Interactive profile switching
        -i|--interactive)
        interactive_selection
        shift
        show_profiles=false
        ;;
        #Create a new profile
        -c|--create)
        numOfArgs=1 # number of switch arguments
        if (( $# < numOfArgs + 1 )); then
echo "Missing profile name for --create.
See $(basename $0) --help for usage info"
            exit 0
        else
            shift
            create_new_profile "${1}"
            shift $((numOfArgs + 1)) # shift 'numOfArgs + 1' to bypass switch and its value
        fi
        show_profiles=false
        ;;
        -r|--reload)
        reload_profile
        show_profiles=false
        shift
        ;;
        -e|--edit)
        edit_current_profile
        show_profiles=false
        shift
        ;;
        #unknown flag/switch
        -*) 
echo "Unknown option ${1}.
See $(basename $0) --help for usage info"
        show_profiles=false
        exit 0
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
    if $show_profiles; then
        current_name=`get_profile_name $SSH_CONFIG_PATH`

        echo "Available profiles:"
        if [[ -n "${current_name}" ]]; then    
            ls -1 $SSH_PROFILE_PATH | nl | sed "s/$current_name/$current_name - active/g"
        else
            ls -1 $SSH_PROFILE_PATH | nl
        fi
    fi
else
    profile=$1
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        profiles=(`ls -1 $SSH_PROFILE_PATH`)
        profile="${profiles[$1-1]}"
        if [[ -z "$profile" ]]; then
            echo "Error: $1 is not a valid profile number."
            exit 1
        fi
    fi
    
    if [ -f "$SSH_PROFILE_PATH/$profile" ]; then
        switch_profile $profile
    else
        echo "Error: Profile \"$profile\" doesn't exist. Use --create to add a new profile." >&2
        exit 1
    fi
fi