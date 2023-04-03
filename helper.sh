#!/bin/bash

DEFAULT_BACKTITLE="Scale3Labs SUI Install Wizard"
DEFAULT_FLAGS="--clear --no-cancel"

# defaults
SUI_RELEASE="testnet"   # can be github release tag, branch, or commit hash
DEFAULT_BINARY_DIR="$(echo ~)/sui"
SUI_RELEASE_OS="sui-node-ubuntu23"
SUI_NETWORK="testnet"   # this can be either devnet or testnet
NODE_TYPE="fullnode"    # this can be either fullnode or validator
CONFIG_TEMPLATE_URL=""  # set to $FULLNODE_CONFIG_TEMPLATE_URL or $VALIDATOR_CONFIG_TEMPLATE_URL based on choice
CONFIG_FILE_NAME=""     # set to 'fullnode.yaml' or 'validator.yaml' based on choice

BINARY_NAME="sui-node"
CLI_NAME="sui"

# to store temporary files
TMP_FOLDER="/tmp/sui-node-helper"

TESTNET_GENESIS_BLOB_URL="https://raw.githubusercontent.com/MystenLabs/sui-genesis/main/testnet/genesis.blob"
DEVNET_GENESIS_BLOB_URL="https://raw.githubusercontent.com/MystenLabs/sui-genesis/main/devnet/genesis.blob"
GENESIS_BLOB_URL="https://raw.githubusercontent.com/MystenLabs/sui-genesis/main/testnet/genesis.blob"
SERVICE_TEMPLATE_URL="https://raw.githubusercontent.com/Scale3-Labs/sui-node-helper/master/sui-node.service"
VALIDATOR_CONFIG_TEMPLATE_URL="https://raw.githubusercontent.com/Scale3-Labs/sui-node-helper/master/validator.yaml"
CLIENT_CONFIG_URL="https://raw.githubusercontent.com/Scale3-Labs/sui-node-helper/master/client.yaml"
FULLNODE_CONFIG_TEMPLATE_URL="https://raw.githubusercontent.com/Scale3-Labs/sui-node-helper/master/fullnode.yaml"

SUI_SERVICE_PATH="/etc/systemd/system/sui-node.service"
CLIENT_CONFIG_PATH="$(echo ~)/.sui/sui_config/client.yaml"

function setup_cancelled {
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --pause "User aborted, exiting..." 10 40 5
    clear
    rm -rf $TMP_FOLDER
    exit 1
}

function setup_failed {
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --pause "Failed, please check logs. Exiting..." 10 40 5
    exit 1      # Do not clear for debugging
}

function download_failed {
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --pause "Failed to download, probably required release does not currently exists in Scale3Labs repository. Exiting..." 0 0 7
    clear
    rm -rf $TMP_FOLDER
    exit 1
}

function not_available {
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --pause "feature currently not available, exiting..." 10 40 5
    clear
    rm -rf $TMP_FOLDER
    exit 1
}

function show_continue_option {
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
    --title "Continue?" \
    --yesno "Do you want to go back to main menu?" 0 0
    if [ $? -ne 0 ]; then
        setup_cancelled
    fi
    show_node_choices
}

function verify_server {
    if [[ $(lsb_release -si) != "Ubuntu" ]]; then
        dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
            --title "Unsupported OS" \
            --yesno "Unsupported OS detected.\nThis script only supports Ubuntu.\n\nDo you still want to take a risk and continue?" 0 0
    fi

    if [[ $(uname -m) != "x86_64" ]]; then
        echo "This script only supports x86_64 or aarch64 architecture. Aborting..."
        dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
            --title "Unsupported Platform" \
            --yesno "This script only supports x86_64.\nYour server is $(uname -m).\n\nDo you still want to take a risk and continue?" 0 0
        if [ $? -ne 0 ]; then
            setup_cancelled
        fi
    fi

    case $(lsb_release -sr) in
      18.*)
          SUI_RELEASE_OS="sui-node-ubuntu18"
          ;;
      20.*)
          SUI_RELEASE_OS="sui-node-ubuntu20"
          ;;
      22.*)
          SUI_RELEASE_OS="sui-node-ubuntu22"
          ;;
      23.*)
          SUI_RELEASE_OS="sui-node-ubuntu23"
          ;;
      *)
          dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
              --title "Unsupported OS" \
              --yesno "Unsupported Ubuntu version. Found $(lsb_release -sr),\nCurrently supported 18, 20, 22 & 23.\n\nPlease raise a github issue to add support for your server.\n\n\nSince we do not have support for your Ubuntu version, it may not work as expected.\nDo you still want to take a risk and continue?" 0 0
          if [ $? -ne 0 ]; then
              setup_cancelled
          fi
          ;;
    esac
}

function show_node_choices {
    choice=$(dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Node Type" \
        --menu "Choose your choice of node:" 15 55 5 \
            1 "Validator Node" \
            2 "RPC Full Node" \
            3 "Exit" \
            2>&1 >/dev/tty)
}

function validator_flow_choice {
    NODE_TYPE="validator"
    CONFIG_FILE_NAME="validator.yaml"
    CONFIG_TEMPLATE_URL=$VALIDATOR_CONFIG_TEMPLATE_URL

    choice=$(dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Validator Node Options" \
        --menu "What do you want to do?" 15 55 5 \
            1 "Setup Validator From Scratch" \
            2 "Update Validator Version" \
            3 "Perform Validator Operations" \
            4 "Wipe Database (coming soon...)" \
            5 "Exit" \
            2>&1 >/dev/tty)
    
    case $choice in
        1) setup_validator_node_flow;;
        2) update_validator_node_flow;;
        3) validator_operations_flow;;
        4) not_available;;
        5) setup_cancelled;;
        *) setup_cancelled;;
    esac
}

function setup_validator_node_flow {

    # Validator Setup Sequence
    select_network
    get_sui_release
    download_binary
    verify_binary
    download_genesis
    initialize_validator_client
    validator_info
    setup_sui_service
    post_node_setup_instructions
}

function update_validator_node_flow {
    # Validator update sequence
    get_sui_release
    stop_sui_node
    download_binary
    verify_binary
    restart_sui_node
    show_continue_option
}

function validator_operations_flow {
    IFS=$'\n' read -r -d '' sui_path < <( dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" --stdout --title "SUI PATH" \
        --form "Operations require having SUI client on the server.\n\nenter directory path to sui client\n- Once entered press Yes to continue.\n- Select 'Cancle' to exit:" 0 0 0 \
        "SUI_FOLDER_PATH:"         1 1 "$(echo ~)/sui" 1 40 80 0
    )
    # If user presses Cancle
    if [ -z "$sui_path" ]; then
        setup_cancelled
    fi
    DEFAULT_BINARY_DIR=$sui_path
    show_supported_validator_operations
}

function fullnode_flow_choice {
    NODE_TYPE="fullnode"
    CONFIG_FILE_NAME="fullnode.yaml"
    CONFIG_TEMPLATE_URL=$FULLNODE_CONFIG_TEMPLATE_URL

    choice=$(dialog $DEFAULT_FLAGS \
    --backtitle "$DEFAULT_BACKTITLE" \
    --title "FullNode Options" \
    --menu "What do you want to do?" 15 55 5 \
        1 "Setup FullNode From Scratch" \
        2 "Update FullNode Version" \
        3 "Setup FullNode with Indexer (coming soon...)" \
        4 "Wipe Database (coming soon...)" \
        5 "Exit" \
        2>&1 >/dev/tty)

    case $choice in
        1) setup_fullnode_node_flow;;
        2) update_fullnode_node_flow;;
        3) not_available;;
        4) not_available;;
        5) setup_cancelled;;
        *) setup_cancelled;;
    esac
}

function setup_fullnode_node_flow {
    # Fullnode Setup Sequence
    select_network
    get_sui_release
    download_binary
    verify_binary
    download_genesis
    setup_sui_service
    post_node_setup_instructions
}

function update_fullnode_node_flow {
    # Fullnode update sequence
    get_sui_release
    stop_sui_node
    download_binary
    verify_binary
    restart_sui_node
    show_continue_option
}

function select_network {
   choice=$(dialog $DEFAULT_FLAGS \
    --backtitle "$DEFAULT_BACKTITLE" \
    --title "Select Network" \
    --menu "Setup FullNode for Network." 15 55 5 \
        1 "Testnet" \
        2 "Devnet" \
        3 "Exit" \
        2>&1 >/dev/tty)
    
    case $choice in
        1)  SUI_NETWORK="testnet"
            GENESIS_BLOB_URL=$TESTNET_GENESIS_BLOB_URL
            ;;
        2)  SUI_NETWORK="devnet"
            GENESIS_BLOB_URL=$DEVNET_GENESIS_BLOB_URL
            ;;
        *) setup_cancelled;;
    esac
}

function get_sui_release {
    binary_form=$(dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Download Binary & CLI" \
        --form "Enter release details: \n\nPress 'OK' to download:" 0 0 5 \
        "Release version or hash:" 1 1 "testnet" 1 30 60 0 \
        "Absolute folder for configs:" 2 1 "$DEFAULT_BINARY_DIR" 2 30 20 0 \
        2>&1 >/dev/tty)

    if [ $? -ne 0 ]; then
        # Handle when user presses ESC
        setup_cancelled
    fi

    SUI_RELEASE=$(echo "$binary_form" | head -n 1)
    DEFAULT_BINARY_DIR=$(echo "$binary_form" | tail -n 1)
    # Make sure the binary directory exists
    mkdir -p $DEFAULT_BINARY_DIR
    cd $DEFAULT_BINARY_DIR
}

function download_binary {
    CLI_URL="https://storage.googleapis.com/scale3-node-binaries-dev/$SUI_RELEASE_OS/$SUI_RELEASE/sui"
    BINARY_URL="https://storage.googleapis.com/scale3-node-binaries-dev/$SUI_RELEASE_OS/$SUI_RELEASE/sui-node"

    (set -o pipefail && \
        mkdir -p $DEFAULT_BINARY_DIR && \
        curl --fail --progress-bar $BINARY_URL --output $DEFAULT_BINARY_DIR/$BINARY_NAME | dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" --title "Downloading" --gauge "Downloading $BINARY_NAME" 10 50 0 && \
        curl --fail --progress-bar $CLI_URL --output $DEFAULT_BINARY_DIR/$CLI_NAME | dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" --title "Downloading" --gauge "Downloading $CLI_NAME CLI" 10 50 0 && \
        dialog $DEFAULT_FLAGS --title "Download Complete" --backtitle "$DEFAULT_BACKTITLE" --pause "Binary downloaded at path $DEFAULT_BINARY_DIR/$BINARY_NAME, proceeding to verify the version..." 10 50 3 && \
        chmod +x $DEFAULT_BINARY_DIR/$BINARY_NAME $DEFAULT_BINARY_DIR/$CLI_NAME) || \
    download_failed
}

function verify_binary {
    $DEFAULT_BINARY_DIR/$BINARY_NAME --version
    if [ $? -ne 0 ]; then
        # Handle when user presses ESC
        dialog $DEFAULT_FLAGS --title "ERROR" --backtitle "$DEFAULT_BACKTITLE" --pause "Binary version check failed. Your OS or downloaded binary might not be supported" 0 0 5
        exit 1
    fi
    $DEFAULT_BINARY_DIR/$BINARY_NAME --version | dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" --programbox "sui-node version" 10 40
}

function download_genesis {
    # Download genesis blob
    set -e
    curl --fail --progress-bar $GENESIS_BLOB_URL --output $DEFAULT_BINARY_DIR/genesis.blob
    set +e
}

function initialize_validator_client {

    dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Setup Validator Config and Keystore" \
        --yesno "Proceed to setup validator keystore?\nThis will create \n  - client.yaml\n  - sui.keystore\n at '~/.sui/sui_config/'\n\nClick 'Yes' to continue or 'No' to abort." 0 0
    response=$?
    case $response in
        1) setup_cancelled;;
        255) setup_cancelled;;
    esac

    mkdir -p ~/.sui/sui_config/     # Ensure folder is created
    $DEFAULT_BINARY_DIR/$CLI_NAME --version
    $DEFAULT_BINARY_DIR/$CLI_NAME client -y
    # Patch client.yaml if testnet
    if [[ $SUI_NETWORK == "testnet" ]]; then
        curl --fail --progress-bar $CLIENT_CONFIG_URL --output $TMP_FOLDER/client.yaml
        cat ~/.sui/sui_config/client.yaml | grep active_address >> $TMP_FOLDER/client.yaml
        sed -i "s|{{HOME_DIRECTORY}}|$(echo ~)|g;" $TMP_FOLDER/client.yaml

        dialog $DEFAULT_FLAGS \
            --backtitle "$DEFAULT_BACKTITLE" \
            --title "Verify the client.yaml config. TAB to navigate, OK to proceed or ESC to abort." \
            --editbox $TMP_FOLDER/client.yaml 0 0 2>$TMP_FOLDER/updatedclient.yaml
        if [ $? -ne 0 ]; then
            setup_cancelled
        fi
        cp $TMP_FOLDER/updatedclient.yaml $CLIENT_CONFIG_PATH
    fi

    chmod 644 $CLIENT_CONFIG_PATH
    KEY_BYTES=$(sed -e 's/[][]//g' -e 's/"//g' -e 's/,//g' ~/.sui/sui_config/sui.keystore)

    $DEFAULT_BINARY_DIR/$CLI_NAME keytool unpack $KEY_BYTES
    $DEFAULT_BINARY_DIR/$CLI_NAME client new-address ed25519 >> $TMP_FOLDER/wallet_recovery.txt
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --title "Wallet Recovery Phrase: Please note down the recovery phrase" --textbox $TMP_FOLDER/wallet_recovery.txt 0 0
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --title "Client Initialized" --pause "Config & keystore generated at path $DEFAULT_BINARY_DIR/ and ~/.sui/ " 10 50 3
}

function validator_info {
    IFS=$'\n' read -r -d '' name description image_url project_url hostname gas_price < <( dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --stdout --title "Validator Information" \
        --form "This information is about your project.\nWARNING: Hyphen '-' is automatically added for empty fields.\n\nEnter your details:" 0 0 0 \
        "VALIDATOR_NAME:"         1 1 "SUI" 1 40 150 0 \
        "VALIDATOR_DESCRIPTION:"  2 1 "SUI Validator Node description" 2 40 150 0 \
        "LOGO_IMAGE_URL:"    3 1 "https://twitter.com/SuiNetwork/photo" 3 40 150 0 \
        "PROJECT_URL:"  4 1 "https://sui.io/" 4 40 150 0 \
        "HOST_IP_OR_DNS:"    5 1 "$HOSTNAME" 5 40 150 0 \
        "GAS_PRICE:"    6 1 "1" 6 40 150 0)

    # Handle when user presses ESC
    if [ -z "$name" ] && [ -z "$description" ] && [ -z "$image_url" ] && [ -z "$project_url" ] && [ -z "$hostname" ] && [ -z "$gas_price" ]; then
        setup_cancelled
    fi
    # if some fields are kept empty by user, set default value to `-`
    if [ -z "$name" ]; then
        name="-"
    fi
    if [ -z "$description" ]; then
        description="-"
    fi
    if [ -z "$image_url" ]; then
        image_url="-"
    fi
    if [ -z "$project_url" ]; then
        project_url="-"
    fi
    if [ -z "$hostname" ]; then
        hostname="-"
    fi
    if [ -z "$gas_price" ]; then
        gas_price="-"
    fi
    # Making sure we are in right directory
    cd $DEFAULT_BINARY_DIR/
    $DEFAULT_BINARY_DIR/$CLI_NAME validator make-validator-info "$name" "$description" "$image_url" "$project_url" "$hostname" "$gas_price"
    
}

function setup_sui_service {
    dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Setup Systemd Service for SUI" \
        --msgbox "Proceed to setup sui-node service?" 0 0
    if [ $? -ne 0 ]; then
        setup_cancelled
    fi

    IFS=$'\n' read -r -d '' data_folder_path < <( dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --stdout --title "SUI Data Folder" \
        --form "Enter absolute path to folder where you want to store SUI blochchain data\n\nPress 'OK' to continue:" 0 0 0 \
        "DATA_FOLDER_PATH:"         1 1 "$(echo ~)/sui" 1 40 80 0
    )
    # If user presses Cancle
    if [ -z "$data_folder_path" ]; then
        setup_cancelled
    fi

    curl -s $CONFIG_TEMPLATE_URL --output $DEFAULT_BINARY_DIR/$CONFIG_FILE_NAME

    sed -i "s|{{BINARY_PATH}}|$DEFAULT_BINARY_DIR|g; s|{{DNS_NAME}}|$hostname|g; s|{{DATA_FOLDER}}|$data_folder_path|g" $DEFAULT_BINARY_DIR/$CONFIG_FILE_NAME
    
    # requires root permissions
    sudo curl -s $SERVICE_TEMPLATE_URL --output $SUI_SERVICE_PATH
    if [ $? -ne 0 ]; then
        echo "unable to sudo"
        exit 1
    fi
    sudo sed -i "s|{{WORK_DIRECTORY}}|$DEFAULT_BINARY_DIR|g; s|{{CONFIG_PATH}}|$DEFAULT_BINARY_DIR/$CONFIG_FILE_NAME|g; s|{{USER}}|$USER|g" $SUI_SERVICE_PATH

    # create DB dirs
    if [[ $NODE_TYPE == "validator" ]]; then
        mkdir -p $data_folder_path/db/authorities_db $data_folder_path/db/authorities_db
    else
        mkdir -p $data_folder_path/suidb
    fi

    systemctl --user enable $SUI_SERVICE_PATH
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --title "Completed" --pause "SUI service setup completed at path $SUI_SERVICE_PATH" 10 50 5

}

function stop_sui_node {
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --title "Stop SUI node" \
        --yesno "Update requires stopping SUI node.\n\nThis will run 'sudo systemctl stop sui-node'.\n\n\nPress 'Yes' to stop or 'No' to cancle." 0 0
    
    if [ $? -ne 0 ]; then
        setup_cancelled
    fi
    sudo systemctl stop sui-node
    if [ $? -ne 0 ]; then
        setup_failed
    fi

    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --title "SUI Stopped" --pause "SUI node stopped." 10 50 5
}

function restart_sui_node {

    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --title "Restart SUI node" \
        --yesno "Do you want to restart SUI node?\n\nThis will run 'sudo systemctl restart sui-node'.\n\n\nPress 'Yes' to restart or 'No' to cancle." 0 0
    
    if [ $? -ne 0 ]; then
        setup_cancelled
    fi

    sudo systemctl restart sui-node
    if [ $? -ne 0 ]; then
        setup_failed
    fi

    dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Validator Updated" \
        --msgbox "Validator has been updated.\nPlease check the validator logs using the command:\n\n   journalctl -fu sui-node" 0 0
    clear
}

function post_node_setup_instructions {
    dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Node Setup Completed" \
        --msgbox "Thank you for giving this project a try.\nIf you would like to monitor your node, visit scale3labs.com\n\n\n\nNow you can start the SUI node by running the following command:\n\n   sudo systemctl start sui-node\n\n\nTo check the logs of sui-node, run the following command:\n\n   journalctl -fu sui-node\n\n\n\n\nReferences:\nhttps://github.com/MystenLabs/sui/blob/main/nre/systemd/README.md\nhttps://docs.sui.io/build/fullnode\nhttps://docs.sui.io/build/validator-node" 0 0
    clear
}

function show_supported_validator_operations {
    choice=$(dialog $DEFAULT_FLAGS --title "Validator Operations" \
        --backtitle "$DEFAULT_BACKTITLE" \
        --menu "What action do you want to perform on validator?" 15 55 5 \
            1 "Rename Validator(Alpha)" \
            2 "Become Candidate" \
            3 "Join Committee" \
            4 "Update Description (coming soon...)" \
            5 "Wipe Database (coming soon...)" \
            6 "Exit" \
            2>&1 >/dev/tty)
    
    case $choice in
        1) rename_validator;;
        2) become_candidate_validator;;
        3) join_committee_validator;;
        4) not_available;;
        5) not_available;;
        6) setup_cancelled;;
        *) setup_cancelled;;
    esac
}

function rename_validator {
    IFS=$'\n' read -r -d '' new_name gas < <( dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --stdout --title "validator.info file path" \
        --form "Enter New Validator Name?\n\n\nNOTE: Renaming is a Transaction on network and requires wallet balance\n\nSelect 'Cancle' to abort!" 0 0 0 \
        "NEW_VALIDATOR_NAME:"         1 1 "$HOSTNAME" 1 40 80 0 \
        "GAS:"                         2 1 "1000" 2 40 80 0
    )

    sui client call --package 0x2 --module sui_system --function update_validator_name --args 0x5 \"$new_name\" --gas-budget $gas
}

function become_candidate_validator {
    IFS=$'\n' read -r -d '' validator_file_path < <( dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --stdout --title "validator.info file path" \
        --form "Is validator info file already created?\n\nNOTE: make sure you have enough funds to run this command.\n\n   If 'Yes' enter path for validator.info file to become candidate\n Select 'Cancle' to create a validator.info file:" 0 0 0 \
        "FILE_PATH:"         1 1 "$(echo ~)/sui" 1 40 150 0
    )
    # If user presses Cancle
    if [ -z "$validator_file_path" ]; then
        validator_info
    fi
    # Verify file existance
    if [ -d "$validator_file_path" ]; then
        if [ -e "$validator_file_path"/validator.info ]; then
                validator_file_path="$validator_file_path"/validator.info
                dialog $DEFAULT_FLAGS \
                    --backtitle "$DEFAULT_BACKTITLE" \
                    --title "validator.info found!!!" --textbox $validator_file_path 0 0
        fi
    elif [ -f "$validator_file_path" ]; then
        dialog $DEFAULT_FLAGS \
            --backtitle "$DEFAULT_BACKTITLE" \
            --title "validator.info found" --textbox $validator_file_path 0 0
    else
        dialog $DEFAULT_FLAGS \
            --backtitle "$DEFAULT_BACKTITLE" \
            --title "File Not Found" \
            --yesno "Could not find file in provided path\n\n\nDo you want to proceed to create new validator.info file?" 0 0
        if [ $? -ne 0 ]; then
            setup_cancelled
        fi
        validator_info
    fi
    cd $DEFAULT_BINARY_DIR/
    $DEFAULT_BINARY_DIR/$CLI_NAME validator become-candidate validator.info 2>&1 | dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Become Candidate Output" \
        --programbox 30 100

    show_continue_option
}

function join_committee_validator {
    dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Join Validator Committee?" \
        --yesno "WARNING: When you officially join the committee but node is not fully up-to-date (not fully synced), you cannot make meaningful contribution to the network and may be subject to peer reporting hence face the risk of reduced staking rewards for you and your delegators. \n\n\nProceed to join?" 0 0
    if [ $? -ne 0 ]; then
        setup_cancelled
    fi

    $DEFAULT_BINARY_DIR/$CLI_NAME validator join-committee 2>&1 | dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Join Committee Output" \
        --programbox 30 100

    show_continue_option
}

# STEP 0: Prerequisites
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is not installed on the system."
  read -p "Do you want to install curl? (y/n) " input
  if [[ $input == "y" || $input == "Y" ]]; then
    sudo apt-get update
    sudo apt-get install -y curl
  else
    echo "Aborted. Exiting the script..."
    exit 0
  fi
fi

if ! command -v dialog >/dev/null 2>&1; then
  echo "required dependency 'dialog' is not installed on the system."
  read -p "Do you want to install dialog? (y/n) " input
  if [[ $input == "y" || $input == "Y" ]]; then
    sudo apt-get update
    sudo apt-get install -y dialog
  else
    echo "Aborted. Exiting the script..."
    exit 0
  fi
fi
# END STEP 0

# STEP 1: Proceed with Installation
# make sure to create tmp folder and it is empty
rm -rf $TMP_FOLDER && mkdir -p $TMP_FOLDER

dialog $DEFAULT_FLAGS \
    --backtitle "$DEFAULT_BACKTITLE" \
    --title "This is a SUI node installer which will help you setup validator and full node." \
    --yesno "Do you want to proceed?" 0 0
response=$?
case $response in
   0) :;;                   # do nothing and continue
   1) setup_cancelled;;
   255) setup_cancelled;;
esac

# check if user is running on supported server
verify_server

# instructions
dialog $DEFAULT_FLAGS \
    --backtitle "$DEFAULT_BACKTITLE" \
    --title "Instructions" \
    --yesno "-> To abort the setup at any point in time, use Exit/No option or press ESC key. \n\n-> Use keyboard arrow keys & TAB to navigate. \n\nClick 'Yes' to continue." 0 0
response=$?
case $response in
   0) show_node_choices;;
   1) setup_cancelled;;
   255) setup_cancelled;;
esac
# END STEP 1

# STEP 2: Node Choice and Flow
case $choice in
    1) validator_flow_choice;;
    2) fullnode_flow_choice;;
    3) setup_cancelled;;
    *) setup_cancelled;;
esac
# END STEP 2

rm -rf $TMP_FOLDER
