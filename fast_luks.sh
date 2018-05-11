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
# This is by default for our use-case.

STAT="fast-luks"
LOGFILE="/tmp/luks$now.log"
SUCCESS_FILE="/tmp/fast-luks.success"

# Defaults
cipher_algorithm='aes-xts-plain64'
keysize='256'
hash_algorithm='sha256'
device='/dev/vdb'
cryptdev='crypt'
mountpoint='/export'
filesystem='ext4'

paranoic=false
non_interactive=false
foreground=false

# luks ini file
luks_cryptdev_file='/tmp/luks-cryptdev.ini'

# lockfile configuration
LOCKDIR=/var/run/fast_luks
PIDFILE=${LOCKDIR}/fast-luks.pid

################################################################################
# VARIABLES

constant="luks_"
cryptdev=$(cat < /dev/urandom | tr -dc "[:lower:]"  | head -c 8)
logs=$(cat < /dev/urandom | tr -dc "[:lower:]"  | head -c 4)    
temp_name="$constant$logs"
now=$(date +"-%b-%d-%y-%H%M%S")

# log levels
time=$(date +"%Y-%m-%d %H:%M:%S")
info="INFO  "$time
debug="DEBUG "$time
warn="WARNING  "$time
error="ERROR "$time

################################################################################
# FUNCTIONS

#____________________________________
# Intro banner
# bash generate random 32 character alphanumeric string (upper and lowercase)

function intro(){

  NEW_PWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

  until [[ $NEW_PWD =~ ^([a-zA-Z+]+[0-9+]+)$ ]]; do
    NEW_PWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
  done

  echo "========================================================="
  echo "                      ELIXIR-Italy"
  echo "               Filesystem encryption script"             
  echo ""
  echo "A password with at least 8 alphanumeric string is needed"
  echo "There's no way to recover your password."
  echo "Example (automatic random generated passphrase):"
  echo "                      ${NEW_PWD}"
  echo ""
  echo "You will be required to insert your password 3 times:"
  echo "  1. Enter passphrase"
  echo "  2. Verify passphrase"
  echo "  3. Unlock your volume"
  echo ""
  echo "The connection will be  automatically closed."
  echo ""
  echo "========================================================="
}

#____________________________________
# Lock/UnLock Section
# http://wiki.bash-hackers.org/howto/mutex
# "trap -l" for signal summary

# exit codes and text for them - additional features nobody needs :-)
ENO_SUCCESS=0; ETXT[0]="ENO_SUCCESS"
ENO_GENERAL=1; ETXT[1]="ENO_GENERAL"
ENO_LOCKFAIL=2; ETXT[2]="ENO_LOCKFAIL"
ENO_RECVSIG=3; ETXT[3]="ENO_RECVSIG"

function lock(){

  # start un/locking attempt
  trap 'ECODE=$?; echo "[$STAT] Exit: ${ETXT[ECODE]}($ECODE)" >&2' 0
  echo -n "[$STAT]: " >&2

    if mkdir "${LOCKDIR}" &>/dev/null; then
      # lock succeeded, I'm storing the PID 
      echo "$$" >"${PIDFILE}"
      echo -e "\n$info [$STAT] Starting log file."

    else

      # lock failed, check if the other PID is alive
      OTHERPID="$(cat "${PIDFILE}")"
      # if cat isn't able to read the file, another instance is probably
      # about to remove the lock -- exit, we're *still* locked
      #  Thanks to Grzegorz Wierzowiecki for pointing out this race condition on
      #  http://wiki.grzegorz.wierzowiecki.pl/code:mutex-in-bash
      if [ $? != 0 ]; then
        echo "$error [$STAT] Another script instance is active: PID ${OTHERPID} " >&2
        exit ${ENO_LOCKFAIL}
      fi

      if ! kill -0 $OTHERPID &>/dev/null; then
        # lock is stale, remove it and restart
        echo "$debug [$STAT] Removing fake lock file of nonexistant PID ${OTHERPID}" >&2
        rm -rf "${LOCKDIR}"
        echo "$debug [$STAT] Restarting LUKS script" >&2
        exec "$0" "$@"
      else
        # lock is valid and OTHERPID is active - exit, we're locked!
        echo "$error [$STAT] Lock failed, PID ${OTHERPID} is active" >&2
        echo "$error [$STAT] Another $STAT process is active" >&2
        echo "$error [$STAT] If you're sure $STAT is not already running," >&2
        echo "$error [$STAT] You can remove $LOCKDIR and restart $STAT" >&2
        exit ${ENO_LOCKFAIL}
      fi
    fi
}

#____________________________________
function unlock(){
  # lock succeeded, install signal handlers before storing the PID just in case 
  # storing the PID fails
  trap 'ECODE=$?;
        echo "$debug [$STAT] Removing lock. Exit: ${ETXT[ECODE]}($ECODE)"  >> "$LOGFILE" 2>&1 
        rm -rf "${LOCKDIR}"' 0

  # the following handler will exit the script upon receiving these signals
  # the trap on "0" (EXIT) from above will be triggered by this trap's "exit" command!
  trap 'echo "$debug [$STAT] Killed by signal."  >> "$LOGFILE" 2>&1 
        exit ${ENO_RECVSIG}' 1 2 3 15
}

#___________________________________
function info(){
  echo "$debug [$STAT] LUKS header information for $device"
  echo "$debug [$STAT] Cipher algorithm: ${cipher_algorithm}"
  echo "$debug [$STAT] Hash algorithm${hash_algorithm}"
  echo "$debug [$STAT] Keysize: ${keysize}"
  echo "$debug [$STAT] Device: ${device}"
  echo "$debug [$STAT] Crypt device: ${cryptdev}"
  echo "$debug [$STAT] Mapper: /dev/mapper/${cryptdev}"
  echo "$debug [$STAT] Mountpoint: ${mountpoint}"
  echo "$debug [$STAT] File system: ${filesystem}"
}

#____________________________________
# Install cryptsetup

function install_cryptsetup(){
  if [[ -r /etc/os-release ]]; then
      . /etc/os-release
      echo $ID
      if [ "$ID" = "ubuntu" ]; then
          echo "$info [$STAT] Distribution: Ubuntu. Using apt."
          apt-get install -y cryptsetup
      else
          echo "$info [$STAT] Distribution: CentOS. Using yum."
          yum install -y cryptsetup-luks pv
      fi
  else
      echo "$info [$STAT] Not running a distribution with /etc/os-release available."
  fi
}

#____________________________________
# Check cryptsetup installation

function check_cryptsetup(){
  echo ""
  echo "$info [$STAT] Check if the required applications are installed..."
  type -P dmsetup &>/dev/null || echo "$info [$STAT] dmestup is not installed. Installing..." #TODO add install device_mapper
  type -P cryptsetup &>/dev/null || { echo "$info [$STAT] cryptsetup is not installed. Installing.."; install_cryptsetup  >> "$LOGFILE" 2>&1; echo "$info [$STAT] cryptsetup installed!"; }
}

#____________________________________
# Check volume 

function check_vol(){
  echo "$debug [$STAT] Check volume..." >> "$LOGFILE" 2>&1

  if [ $(mount | grep -c $mountpoint) == 0 ]; then # grep -c counts recurrence number.
      echo "$error [$STAT] Device not mounted, exiting!"
      echo "$error [$STAT] Please check logfile: $LOGFILE"
      echo "$error [$STAT] No device  mounted to $mountpoint:" >> "$LOGFILE" 2>&1
      df -h >> "$LOGFILE" 2>&1
      unlock # unlocking script instance
      exit 1
  else
    device=$(df -P $mountpoint | tail -1 | cut -d' ' -f 1)
    echo "$debug [$STAT] Device name: $device" >> "$LOGFILE" 2>&1
  fi
}

#____________________________________
# Umount volume

function umount_vol(){
  echo ""
  echo "$info [$STAT] Unmounting device..."
  umount $mountpoint
  echo "$info [$STAT] $device umounted, ready for encryption!"
}

#____________________________________
function setup_device(){
  echo ""
  echo "$info [$STAT] Using $cipher_algorithm algorithm to luksformat the volume."
  echo "\n$debug [$STAT] Start cryptsetup" >> "$LOGFILE" 2>&1
  info >> "$LOGFILE" 2>&1
  echo "$debug [$STAT] cryptsetup full command:" >> "$LOGFILE" 2>&1 
  echo "$debug [$STAT] cryptsetup -v --cipher $cipher_algorithm --key-size $keysize --hash $hash_algorithm --iter-time 2000 --use-urandom --verify-passphrase luksFormat $device --batch-mode" >> "$LOGFILE" 2>&1 
  cryptsetup -v --cipher $cipher_algorithm --key-size $keysize --hash $hash_algorithm --iter-time 2000 --use-urandom --verify-passphrase luksFormat $device --batch-mode
  ecode=$?
  if [ $ecode != 0 ]; then
    ### start log
    echo "$error [$STAT] Command cryptsetup failed! Mounting $device to $mountpoint again." >> "$LOGFILE" 2>&1 #TODO redirect exit code
    ### end log
    mount $device $mountpoint >> "$LOGFILE" 2>&1
    unlock
    exit 1
  fi
}

#____________________________________
function open_device(){
  echo ""
  echo "$info [$STAT] Open LUKS volume."
  if [ ! -b /dev/mapper/${cryptdev} ]; then
    cryptsetup luksOpen $device $cryptdev
  else
    echo "$error [$STAT] Crypt device already exists! Please check logs: $LOGFILE"
    echo "$error [$STAT] Unable to luksOpen device. " >> "$LOGFILE" 2>&1
    echo "$error [$STAT] /dev/mapper/${cryptdev} already exists." >> "$LOGFILE" 2>&1
    echo "$error [$STAT]  Mounting $device to $mountpoint again." >> "$LOGFILE" 2>&1
    mount $device $mountpoint >> "$LOGFILE" 2>&1
    unlock # unlocking script instance
    exit 1
  fi
}

#____________________________________
function encryption_status(){
  echo ""
  echo "$info [$STAT] check $cryptdev status with cryptsetup status"
  cryptsetup -v status $cryptdev
}

#____________________________________
# Create block file
# https://wiki.archlinux.org/index.php/Dm-crypt/Device_encryption
# https://wiki.archlinux.org/index.php/Dm-crypt/Drive_preparation
# https://wiki.archlinux.org/index.php/Disk_encryption#Preparing_the_disk
#
# Before encrypting a drive, it is recommended to perform a secure erase of the disk by overwriting the entire drive with random data.
# To prevent cryptographic attacks or unwanted file recovery, this data is ideally indistinguishable from data later written by dm-crypt.

function wipe_data(){
  echo ""
  echo "$info [$STAT] Wiping disk data by overwriting the entire drive with random data"
  echo "$info [$STAT] This might take time depending on the size & your machine!"

  #dd if=/dev/zero of=/dev/mapper/${cryptdev} bs=1M  status=progress
  pv -tpreb /dev/zero | dd of=/dev/mapper/${cryptdev} bs=1M status=progress;

  echo "$debug [$STAT] Block file /dev/mapper/${cryptdev} created."
  echo "$debug [$STAT] Wiping done."
}

#____________________________________
function create_fs(){
  echo ""
  echo "$info [$STAT] Creating filesystem..."
  mkfs.${filesystem} /dev/mapper/${cryptdev} #Do not redirect mkfs, otherwise no interactive mode!
  if [ $? != 0 ]; then
    echo "$error [$STAT] While creating ${filesystem} filesystem. Please check logs: $LOGFILE"
    echo "$error [$STAT] Command mkfs failed!"
    unlock
    exit 1
  fi
}

#____________________________________
function mount_vol(){
  echo ""
  echo "$info [$STAT] Mounting encrypted device..."
  mount /dev/mapper/${cryptdev} $mountpoint
  df -Hv >> "$LOGFILE" 2>&1
}

#____________________________________
function create_cryptdev_ini_file(){
  echo "# This file has been generated using fast_luks.sh script" > ${luks_cryptdev_file}
  echo "# https://github.com/mtangaro/galaxycloud-testing/blob/master/fast_luks.sh" >> ${luks_cryptdev_file}
  echo "# The device name could change after reboot, please use UUID instead." >> ${luks_cryptdev_file}
  echo "# LUKS provides a UUID \(Universally Unique Identifier\) \for each device." >> ${luks_cryptdev_file}
  echo "# This, unlike the device name \(eg: /dev/vdb\), is guaranteed to remain constant" >> ${luks_cryptdev_file}
  echo "# as long as the LUKS header remains intact." >> ${luks_cryptdev_file}
  echo "#" >> ${luks_cryptdev_file}
  echo "# LUKS header information for $device" >> ${luks_cryptdev_file}
  echo -e "# luks-${now}\n" >> ${luks_cryptdev_file}
  
  echo "[luks]" >> ${luks_cryptdev_file}
  echo "cipher_algorithm = ${cipher_algorithm}" >> ${luks_cryptdev_file}
  echo "hash_algorithm = ${hash_algorithm}" >> ${luks_cryptdev_file}
  echo "keysize = ${keysize}" >> ${luks_cryptdev_file}
  echo "device = ${device}" >> ${luks_cryptdev_file}
  echo "uuid = $(cryptsetup luksUUID ${device})" >> ${luks_cryptdev_file}
  echo "cryptdev = ${cryptdev}" >> ${luks_cryptdev_file}
  echo "mapper = /dev/mapper/${cryptdev}" >> ${luks_cryptdev_file}
  echo "mountpoint = ${mountpoint}" >> ${luks_cryptdev_file}
  echo "filesystem = ${filesystem}" >> ${luks_cryptdev_file}

  # Update Log file
  dmsetup info /dev/mapper/${cryptdev}
  cryptsetup luksDump $device
}

#____________________________________
function end_encrypt_procedure(){
  echo ""
  # send signal to unclok waiting condition for automation software (e.g Ansible)
  echo "LUKS encryption completed." > $SUCCESS_FILE # WARNING DO NOT MODFIFY THIS LINE, THIS IS A CONTROL STRING FOR ANSIBLE
  echo "$info [$STAT] SUCCESSFUL."
}

#____________________________________
#FIXME cryptsetup (temporary version)

function encrypt(){
  # Check which virtual volume is mounted to /export
  check_vol

  # Umount volume.
  umount_vol  >> "$LOGFILE" 2>&1

  # Setup a new dm-crypt device
  setup_device

  # Create mapping
  open_device

  # Check status
  encryption_status >> "$LOGFILE" 2>&1
  
  if [[ $foreground == false ]]; then

    # Run this in background. 
    echo "$info [$STAT] Run script in backgroud."

    (
      # Wipe data for security
      # WARNING This is going take time, depending on VM storage. Currently commented out
      if [[ $paranoic == true ]]; then wipe_data >> "$LOGFILE" 2>&1; fi
    
      # Create filesystem
      create_fs >> "$LOGFILE" 2>&1
    
      # Mount volume
      mount_vol >> "$LOGFILE" 2>&1
    
      # Create ini file
      create_cryptdev_ini_file >> "$LOGFILE" 2>&1
    
      # LUKS encryption finished. Print end dialogue.
      end_encrypt_procedure >> "$LOGFILE" 2>&1
    
      # Unlock once done.
      unlock >> "$LOGFILE" 2>&1
    ) &

  elif [[ $foreground == true ]]; then

    echo "$info [$STAT] Run script in foreground."

    if [[ $paranoic == true ]]; then wipe_data; fi
    create_fs
    mount_vol
    create_cyptdev_ini_file
    end_encrypt_procedure
    unlock >> "$LOGFILE" 2>&1

  fi # end foregroud if

}

################################################################################
# Main script

# Check if script is run as root
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "$error [$STAT] Not running as root."
    exit 1
fi

# Create lock file. Ensure only single instance running.
lock >> "$LOGFILE" 2>&1

# If running script with no arguments then loads defaults values.
if [ $# -lt 1 ]; then
  echo -e "\n$error [$STAT] No inputs. Using defaults values:" >> "$LOGFILE" 2>&1
  info >> "$LOGFILE" 2>&1
fi

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

    --paranoic-mode) paranoic=true;;

    # TODO implement non-interactive mode. Allow to pass password from command line.
    # TODO Currently it just avoid to print intro and deny random password generation.
    # TODO Allow to inject passphrase from command line (not secure)
    # TODO create a "--password" option to inject password.
    --non-interactive) non_interactive=true;;

    --foreground) foreground=true;; # run script in foregrond, allowing to use it on ansible playbooks.

    --default) DEFAULT=YES;;

    -h|--help) print_help=true;;

    -*) echo >&2 "usage: $0 [--help] [print all options]"
	exit 1;;
    *) echo >&2 "Loading defaults"; DEFAULT=YES;; # terminate while loop
  esac
  shift
  echo "$debug [$STAT] Custom options:" >> "$LOGFILE" 2>&1
  info >> "$LOGFILE" 2>&1
done

if [[ -n $1 ]]; then
    echo "$info [$STAT] Last line of file specified as non-opt/last argument:"
    tail -1 $1
fi

# Print Help
if [[ $print_help = true ]]
  then
    echo ""
    usage="$(basename "$0"): a bash script to automate LUKS file system encryption.\n
           usage: fast-luks [-h]\n
           \n
           optionals argumets:\n
           -h, --help			\t\tshow this help text\n
           -c, --cipher			\t\tset cipher algorithm [default: aes-xts-plain64]\n
           -k, --keysize		\t\tset key size [default: 256]\n
           -a, --hash_algorithm		\tset hash algorithm used for key derivation\n
           -d, --device			\t\tset device [default: /dev/vdb]\n
           -e, --cryptdev		\tset crypt device [default: cryptdev]\n
           -m, --mountpoint		\tset mount point [default: /export]\n
           -f, --filesystem		\tset filesystem [default: ext4]\n
           --default			\t\tload default values\n"
    echo -e $usage
    echo -e "\n$info [$STAT] Just printing help." >> "$LOGFILE" 2>&1
    unlock
    exit 0
fi

# Print intro
if [[ $non_interactive == false ]]; then intro; fi

# Check if the required applications are installed
check_cryptsetup

# Encrypt volume
encrypt
