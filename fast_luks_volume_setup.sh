#!/bin/bash

STAT="fast-luks-volume-setup"
if [[ ! -v LOGFILE ]]; then LOGFILE="/tmp/luks_volume_setup.log"; fi
if [[ ! -v SUCCESS_FILE_DIR ]]; then SUCCESS_FILE_DIR=/var/run; fi
SUCCESS_FILE="${SUCCESS_FILE_DIR}/fast-luks-volume-setup.success"

# lockfile configuration
LOCKDIR=/var/run/fast_luks
PIDFILE=${LOCKDIR}/fast-luks-volume-setup.pid

# Load functions
if [[ -f ./fast_luks_lib.sh ]]; then
  source ./fast_luks_lib.sh
else
  echo '[Error] No fast_luks_lib.sh file found.'
  exit 1
fi

# Check if script is run as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo_error "Not running as root."
    exit 1
fi

# Create lock file. Ensure only single instance running.
lock "$@"

# Start Log file
logs_info "Start log file: $(date +"%b-%d-%y-%H%M%S")"

# Loads defaults values then take user custom parameters.
# The only variables needed are:
# - if paranoid mode is enabled
# - luks-cryptdev.ini file location
load_default_config

# Read luks-cryptdev.ini file to setup all variables (mostly device mapper).
read_ini_file luks_cryptdev_file 

# Parse CLI options
while [ $# -gt 0 ]
do
  case $1 in
    -d|--device) device="$2"; shift ;;

    -e|--cryptdev) cryptdev="$2"; shift ;;

    -m|--mountpoint) mountpoint="$2"; shift ;;

    -f|--filesystem) filesystem="$2"; shift ;;

    --paranoid-mode) paranoid=true;;

    --default) DEFAULT=YES;;

    -h|--help) print_help=true;;

    -*) echo >&2 "usage: $0 [--help] [print all options]"
        exit 1;;
    *) DEFAULT=YES;; # terminate while loop
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
         -d, --device                 \t\tset device [default: /dev/vdb]\n
         -e, --cryptdev               \tset crypt device. This is randomly generated during the encryption procedure, read from the luks-crypt.ini file, but still settable. [default: cryptdev]\n
         -m, --mountpoint             \tset mount point [default: /export]\n
         -f, --filesystem             \tset filesystem [default: ext4]\n
         --paranoid-mode              \twipe data after encryption procedure. This take time [default: false]\n
         --default                    \t\tload default values from defaults.conf\n"
  echo -e $usage
  logs_info "Just printing help."
  unlock
  exit 0
elif [[ ! -v print_help ]]; then
    info >> "$LOGFILE" 2>&1
fi

#____________________________________
#____________________________________
#____________________________________
# VOLUME SETUP

# Wipe data for security
# WARNING This is going take time, depending on VM storage. Currently commented out
if [[ $paranoid == true ]]; then wipe_data; fi

# Create filesystem
create_fs

# Mount volume
mount_vol

# Update ini file
create_cryptdev_ini_file

# Volume setup finished. Print end dialogue.
end_volume_setup_procedure

# Unlock once done.
unlock >> "$LOGFILE" 2>&1
