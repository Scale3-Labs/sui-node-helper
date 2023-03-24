#!/bin/bash

DEFAULT_BACKTITLE="Scale3Labs SUI Install Wizard"
DEFAULT_FLAGS="--clear --no-cancel"

# defaults
SUI_RELEASE="testnet"   # can be github release tag, branch, or commit hash
DEFAULT_BINARY_DIR="$(echo ~)/sui"
SUI_RELEASE_OS="sui-node-ubuntu23"

BINARY_NAME="sui-node"
CLI_NAME="sui"

GENESIS_BLOB_URL="https://raw.githubusercontent.com/Scale3-Labs/sui-node-helper/master/genesis.blob"
SERVICE_TEMPLATE_URL="https://raw.githubusercontent.com/Scale3-Labs/sui-node-helper/master/genesis.blob"
VALIDATOR_CONFIG_TEMPLATE_URL="https://raw.githubusercontent.com/Scale3-Labs/sui-node-helper/master/validator.yaml"

SUI_SERVICE_PATH="/etc/systemd/system/sui-node.service"
CLIENT_CONFIG='keystore:
  File: sui.keystore
envs:
  - alias: testnet
    rpc: "https://wave3-rpc.testnet.sui.io:443"
    ws: ~
active_env: testnet'

function setup_cancelled {
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --pause "User aborted, exiting..." 10 40 5
    clear
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
    exit 1
}

function not_available {
    dialog $DEFAULT_FLAGS --backtitle "$DEFAULT_BACKTITLE" \
        --pause "feature currently not available, exiting..." 10 40 5
    clear
    exit 1
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
    choice=$(dialog $DEFAULT_FLAGS --title "Node Type" \
        --backtitle "$DEFAULT_BACKTITLE" \
        --menu "Choose your choice of node:" 15 55 5 \
            1 "Validator Node" \
            2 "RPC Node (coming soon...)" \
            3 "Exit" \
            2>&1 >/dev/tty)
}

function validator_flow_choice {
    choice=$(dialog $DEFAULT_FLAGS --title "Validator Node Options" \
        --backtitle "$DEFAULT_BACKTITLE" \
        --menu "What do you want to do?" 15 55 5 \
            1 "Setup Validator From Scratch" \
            2 "Update Validator Version" \
            3 "Wipe Database (coming soon...)" \
            4 "Exit" \
            2>&1 >/dev/tty)
    
    case $choice in
        1) setup_validator_node_flow;;
        2) update_validator_node_flow;;
        3) not_available;;
        4) setup_cancelled;;
        *) setup_cancelled;;
    esac
}

function setup_validator_node_flow {

    # Validator Setup Sequence
    get_sui_release
    download_binary
    verify_binary
    initialize_client
    validator_info
    setup_sui_service
    post_validator_setup_instructions
}

function update_validator_node_flow {

    # Validator update sequence
    get_sui_release
    download_binary
    verify_binary
    restart_sui_node
}

function setup_rpc_node_flow {
    not_available
}

function get_sui_release {
    binary_form=$(dialog $DEFAULT_FLAGS --title "Download Binary & CLI" \
        --backtitle "$DEFAULT_BACKTITLE" \
        --form "Enter release details: \n\nPress 'OK' to download:" 0 0 5 \
        "Release version or hash:" 1 1 "testnet" 1 30 60 0 \
        "Absolute folder for data:" 2 1 "$DEFAULT_BINARY_DIR" 2 30 20 0 \
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

function initialize_client {
    # Download genesis blob
    curl --fail --progress-bar $GENESIS_BLOB_URL --output $DEFAULT_BINARY_DIR/genesis.blob

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
    echo "$CLIENT_CONFIG" > ~/.sui/sui_config/client.yaml
    chmod 644 ~/.sui/sui_config/client.yaml
    KEY_BYTES=$(sed -e 's/[][]//g' -e 's/"//g' -e 's/,//g' ~/.sui/sui_config/sui.keystore)

    $DEFAULT_BINARY_DIR/$CLI_NAME keytool unpack $KEY_BYTES
    $DEFAULT_BINARY_DIR/$CLI_NAME client new-address ed25519
    dialog $DEFAULT_FLAGS --title "Client Initialized" --pause "Config & keystore generated at path $DEFAULT_BINARY_DIR/ and ~/.sui/ " 10 50 3
}

function validator_info {
    IFS=$'\n' read -r -d '' name description image_url project_url hostname gas_price < <( dialog $DEFAULT_FLAGS --stdout --title "Validator Information" \
        --form "This information is about your project.\nWARNING: do not keep any fields blank, just add '-' or '.' for empty fields.\n\nEnter your details:" 0 0 0 \
        "VALIDATOR_NAME:"         1 1 "SUI" 1 20 150 0 \
        "VALIDATOR_DESCRIPTION:"  2 1 "SUI Validator Node description" 2 20 150 0 \
        "LOGO_IMAGE_URL:"    3 1 "https://twitter.com/SuiNetwork/photo" 3 20 150 0 \
        "PROJECT_URL:"  4 1 "https://sui.io/" 4 20 150 0 \
        "HOST_IP_OR_DNS:"    5 1 "$HOSTNAME" 5 20 150 0 \
        "GAS_PRICE:"    6 1 "1" 6 20 150 0)
    
    # if [ $? -ne 0 ]; then
    #     # Handle when user presses ESC
    #     setup_cancelled
    # fi

    # if fields are kept empty by user, set default value to `-`
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

    curl -s $VALIDATOR_CONFIG_TEMPLATE_URL --output $DEFAULT_BINARY_DIR/validator.yaml
    sed -i "s|{{BINARY_PATH}}|$DEFAULT_BINARY_DIR|g; s|{{DNS_NAME}}|$hostname|g" $DEFAULT_BINARY_DIR/validator.yaml
    
    # requires root permissions
    sudo curl -s $SERVICE_TEMPLATE_URL --output $SUI_SERVICE_PATH
    if [ $? -ne 0 ]; then
        echo "unable to sudo"
        exit 1
    fi
    sudo sed -i "s|{{WORK_DIRECTORY}}|$DEFAULT_BINARY_DIR|g; s|{{CONFIG_PATH}}|$DEFAULT_BINARY_DIR/validator.yaml|g; s|{{USER}}|$USER|g" $SUI_SERVICE_PATH

    # create DB dirs
    mkdir -p $DEFAULT_BINARY_DIR/db/authorities_db $DEFAULT_BINARY_DIR/db/consensus_db

    systemctl --user enable $SUI_SERVICE_PATH

    dialog $DEFAULT_FLAGS --title "Completed" --pause "SUI service setup completed at path $SUI_SERVICE_PATH" 10 50 5

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

function post_validator_setup_instructions {
    dialog $DEFAULT_FLAGS \
        --backtitle "$DEFAULT_BACKTITLE" \
        --title "Validator Setup Completed" \
        --msgbox "Thank you for giving this project a try.\nIf you would like to monitor your node, visit scale3labs.com\n\n\n\nNow you can start the SUI node by running the following command:\n\n   sudo systemctl start sui-node\n\n\nTo check the logs of sui-node, run the following command:\n\n   journalctl -fu sui-node\n\n\n\n\nReferences:\nhttps://github.com/SuiExternal/sui-testnet-wave3/blob/main/validator_operations/join_committee.md\nhttps://github.com/MystenLabs/sui/blob/main/nre/systemd/README.md" 0 0
    clear
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
    --yesno "-> To abort the setup at any point in time, use Exit/No option or press ESC key. \n\n-> Use keyboard arrow keys to navigate. \n\nClick 'Yes' to continue." 0 0
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
    2) setup_rpc_node_flow;;
    3) setup_cancelled;;
    *) setup_cancelled;;
esac
# END STEP 2
