# SUI Node Helper

Welcome to the repository for the SUI blockchain node setup and update helper script!

This GitHub repository contains a Bash script that automates the process of setting up and updating a SUI blockchain node. The script is designed to be easy to use, even for users who are not experienced with command-line interfaces.

To use the helper script in this repository, simply download the script and run it on your system. The script will guide you through the process of setting up and updating your SUI blockchain node.

## Requirements

- curl to download required files.
- dialog for user interface.
- systemd to run `sui-node` service.
- An Ubuntu server capable of running SUI validator or full node, with required open ports.

Running a validator requires mist on your validator address, so make sure you have enough mist after you setup your node.

## Instructions

> **NOTE**: Some commands would require sudo permissions to run, please ensure your logged in user has required permissions.

### Setup SUI Validator

- SSH into the server where you want to set up the SUI node.
- Download the `helper.sh` by running the following command on server.
  ```bash
  curl --fail --location --output helper.sh https://raw.githubusercontent.com/Scale3-Labs/sui-node-helper/master/helper.sh 
  ```
- Give executable permissions to the script.
  ```bash
  chmod +x helper.sh
  ```
- Run the script.
  ```bash
  ./helper.sh
  ```
- Follow the instructions to setup sui-node service.
- Once setup, start the service using the following command.
  ```bash
  service sui-node start
  ```
- To check the logs, run the following command
  ```bash
  journalctl -fu sui-node
  ```

### Update SUI Validator Version

Works for sui node which is setup as systemd service with name `sui-node`.

- SSH into the validator.
- Download `helper.sh`
- Give executable permissions to the script.
  ```bash
  chmod +x helper.sh
  ```
- Run the script.
  ```bash
  ./helper.sh
  ```
- Follow the instructions to update validator.
- Check logs by running
  ```bash
  journalctl -fu sui-node
  ```



Interested in setting up monitoring for your SUI node? Head on to [scale3labs.com](https://www.scale3labs.com/#autopilot).

## Support

For any issues, initiate a GitHub issue on this repo or you can join our [discord](https://discord.gg/h74CkNv4h9) for queries.
