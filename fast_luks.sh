#!/bin/bash

STAT="fast-luks-interface"
export LOGFILE="/tmp/fast_luks$(date +"-%b-%d-%y-%H%M%S").log"

script_name=$0
script_full_path=$(dirname "$0")
cd $script_full_path

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
# Parse CLI options
while [ $# -gt 0 ]
do
  case $1 in
    -c|--cipher) cipher_algorithm="$2"; shift;;

    -k|--keysize) keysize="$2"; shift;;

    -a|--hash_algorithm) hash_algorithm="$2"; shift;;

    -d|--device) device="$2"; shift ;;

    -e|--cryptdev) cryptdev="$2"; shift ;;

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

# Print intro
if [[ $non_interactive == false ]]; then intro; fi

#____________________________________
#____________________________________
#____________________________________
# MAIN SCRIPT

# VOLUME ENCRYPTION
./fast_luks_encryption.sh

# VOLUME SETUP
if [[ $foreground == false ]]; then
  # Run this in background.
  nohup ./fast_luks_volume_setup.sh &
elif [[ $foreground == true ]]; then
  ./fast_luks_volume_setup.sh
fi
