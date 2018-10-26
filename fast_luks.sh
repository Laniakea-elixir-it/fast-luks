#!/bin/bash
# Bash script for managing LUKS volumes in Linux:
# You can create a virtual encrypted Linux FS volume from a file block.
# Helps you mount and unmount LUKS partitions.
#
# Author: Marco Tangaro
# Mail: ma.tangaro@ibiom.cnr.it
# Home institution: IBIOM-CNR, ELIXIR-ITALY
#
# Please find the original script here:
# https://github.com/JohnTroony/LUKS-OPs/blob/master/luks-ops.sh
# All credits to John Troon.
#
# The script is able to detect the $device only if it is mounted.
# Otherwise it will use default $device and $mountpoint.

STAT="fast-luks-interface"
export LOGFILE="/var/log/galaxy/fast_luks$(date +"-%b-%d-%y-%H%M%S").log"
#export LOGFILE="/tmp/fast_luks.log"

script_name=$0
script_full_path=$(dirname "$0")
cd $script_full_path

# Force applications to use the default language for output
export LC_ALL=C

#____________________________________
# Load functions
if [[ -f ./fast_luks_lib.sh ]]; then
  source ./fast_luks_lib.sh
else
  echo '[Error] No fast_luks_lib.sh file found.'
  exit 1
fi

#____________________________________
# Check if script is run as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo_error "Not running as root."
    exit 1
fi

#____________________________________
# Start Log file
logs_info "Start log file: $(date +"%b-%d-%y-%H%M%S")"

#____________________________________
# Loads defaults values then take user custom parameters.
load_default_config

#____________________________________
# Parse CLI options

# Store CLI parameters
Npar=$#

# CLI options
while [ $# -gt 0 ]
do
  case $1 in
    -c|--cipher) cipher_algorithm="$2"; shift;;

    -k|--keysize) keysize="$2"; shift;;

    -a|--hash_algorithm) hash_algorithm="$2"; shift;;

    -d|--device) device="$2"; shift ;;

    -e|--cryptdev) cryptdev_new="$2"; shift ;;

    -m|--mountpoint) mountpoint="$2"; shift ;;

    -p|--passphrase) passphrase="$2"; shift ;;  #TODO to be implemented passphrase option for web-UI

    -f|--filesystem) filesystem="$2"; shift ;;

    --paranoid-mode) paranoid=true;;

    # TODO implement non-interactive mode. Allow to pass password from command line.
    # TODO Currently it just avoid to print intro and deny random password generation.
    # TODO Allow to inject passphrase from command line (not secure)
    # TODO create a "--passphrase" option to inject password.
    --non-interactive) non_interactive=true;;

    --foreground) foreground=true;; # run script in foregrond, allowing to use it on ansible playbooks.

    --default) DEFAULT=YES;;

    -h|--help) print_help=true;;

    -*) echo >&2 "usage: $0 [--help] [print all options]"
        exit 1;;
    *) export DEFAULT=YES;; # terminate while loop
  esac
  shift
done

if [[ -n "$1" ]]; then
    logs_info "Last line of file specified as non-opt/last argument:"
    tail -1 $1
fi

# Print Help
if [[ $print_help = true ]]; then
  echo ""
  usage="$(basename "$0"): a bash script to automate LUKS file system encryption.\n
         usage: fast-luks [-h]\n
         \n
         optionals argumets:\n
         -h, --help                   \t\tshow this help text\n
         -c, --cipher                 \t\tset cipher algorithm [default: aes-xts-plain64]\n
         -k, --keysize                \t\tset key size [default: 256]\n
         -a, --hash_algorithm         \tset hash algorithm used for key derivation\n
         -d, --device                 \t\tset device [default: /dev/vdb]\n
         -e, --cryptdev               \tset crypt device [default: cryptdev]\n
         -m, --mountpoint             \tset mount point [default: /export]\n
         -f, --filesystem             \tset filesystem [default: ext4]\n
         --paranoid-mode              \twipe data after encryption procedure. This take time [default: false]\n
         --non-interactive            \tnon-interactive mode, only command line [default: false]\n
         --foreground                 \t\trun script in foreground [default: false]\n
         --default                    \t\tload default values from defaults.conf\n"
  echo -e $usage
  logs_info "Just printing help."
  unlock
  exit 0
elif [[ ! -v print_help ]]; then
    info >> "$LOGFILE" 2>&1
fi

#____________________________________
function encryption_script_exit(){
  ec=$1
  if [[ $ec != 0 ]]; then
    echo_error "Please try again."
    unset LC_ALL
    exit $ec;
  fi
}

#____________________________________
# Build luks encryption command for different options
function build_luks_ecryption_cmd(){

  # set local cmd variable
  cmd=$cmd_encryption

  if [[ $Npar -eq 0 ]]; then

    # without options the script goes background.
    :

  # if defaults are set, return defaults
  elif [[ $DEFAULT == "YES" ]]; then

    cmd="$cmd --default"
  
  else
  
    cmd="$cmd -c $cipher_algorithm -k $keysize -a $hash_algorithm -d $device -m $mountpoint"

    if [[ -v cryptdev_new ]]; then cmd="$cmd -e $cryptdev_new"; fi

  fi

  # finally assign cmd to cmd_encryption
  cmd_encryption=$cmd

}

#____________________________________
# Build volume setup command for different options

function build_volume_setup_cmd(){

  # set local cmd variable
  cmd=$cmd_volume_setup

  if [[ $Npar -eq 0 ]]; then

    # without options the script goes background.
    :

  elif [[ $Npar -eq 1 && $foreground == true ]]; then

    # with only the foreground option enabled, the next conditionals are skipped
    # so no nohup and no background.
    # Nothing to do
    :

  # if defaults are set, return defaults
  elif [[ $DEFAULT == "YES" ]]; then
    cmd="$cmd  --default"

  else

    cmd="$cmd -d $device -m $mountpoint -f $filesystem"

    if [[ -v cryptdev_new ]]; then cmd="$cmd -e $cryptdev_new"; fi

    if [[ -v paranoid && $paranoid == true ]]; then cmd="$cmd --paranoid-mode"; fi

  fi


  if [[ $foreground == false ]]; then cmd="nohup $cmd &>$LOGFILE &"; fi

  # finally assign cmd to cmd_volume_setup
  cmd_volume_setup=$cmd

}

#____________________________________
#____________________________________
#____________________________________
# MAIN SCRIPT


# Set two global variables for encryption and volume setup commands.
cmd_encryption='./fast_luks_encryption.sh'
cmd_volume_setup='./fast_luks_volume_setup.sh'


# Build commands and run it
build_luks_ecryption_cmd
eval $cmd_encryption
encryption_script_exit $?

build_volume_setup_cmd
eval $cmd_volume_setup

unset LC_ALL

# Wait volume setup script start
# the pid file name is hard-coded in fast_luks_volume_setup.sh
while ! test -f "/var/run/fast_luks/fast-luks-volume-setup.pid"; do
  sleep 1
done
