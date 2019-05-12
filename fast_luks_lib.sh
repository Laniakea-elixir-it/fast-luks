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


################################################################################
# VARIABLES

now=$(date +"-%b-%d-%y-%H%M%S")

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
  echo "========================================================="
}

#____________________________________
# Log levels:
# DEBUG
# INFO
# WARNING
# ERROR
# usege: logs(loglevel, statement, logfile)

# log levels
time=$(date +"%Y-%m-%d %H:%M:%S")
info="INFO  "$time
debug="DEBUG "$time
warn="WARNING "$time
error="ERROR "$time

# echo functions
function echo_debug(){ echo -e "$debug [$STAT] $1"; }
function echo_info(){ echo -e "$info [$STAT] $1"; }
function echo_warn(){ echo -e "$warn [$STAT] $1"; }
function echo_error(){ echo -e "$error [$STAT] $1"; }

# Logs functions
function logs_debug(){ echo_debug "$1" >> $LOGFILE 2>&1; }
function logs_info(){ echo_info "$1" >> $LOGFILE 2>&1; }
function logs_warn(){ echo_warn "$1" >> $LOGFILE 2>&1; }
function logs_error(){ echo_error "$1" >> $LOGFILE 2>&1; }

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

    if mkdir "${LOCKDIR}" &>/dev/null; then
      # lock succeeded, I'm storing the PID 
      echo "$$" >"${PIDFILE}"

    else

      # lock failed, check if the other PID is alive
      OTHERPID="$(cat "${PIDFILE}")"
      # if cat isn't able to read the file, another instance is probably
      # about to remove the lock -- exit, we're *still* locked
      #  Thanks to Grzegorz Wierzowiecki for pointing out this race condition on
      #  http://wiki.grzegorz.wierzowiecki.pl/code:mutex-in-bash
      if [ $? != 0 ]; then
        echo_error "Another script instance is active: PID ${OTHERPID}." >&2
        exit ${ENO_LOCKFAIL}
      fi

      if ! kill -0 $OTHERPID &>/dev/null; then
        # lock is stale, remove it and restart
        echo_debug "Removing fake lock file of nonexistant PID ${OTHERPID}"
        rm -rf "${LOCKDIR}"
        echo_debug "Restarting LUKS script" >&2
        exec "$0" "$@"
      else
        # lock is valid and OTHERPID is active - exit, we're locked!
        echo_error "Lock failed, PID ${OTHERPID} is active" >&2
        echo_error "Another $STAT process is active" >&2
        echo_error "If you're sure $STAT is not already running," >&2
        echo_error "You can remove $LOCKDIR and restart $STAT" >&2
        exit ${ENO_LOCKFAIL}
      fi
    fi
}

#____________________________________
function unlock(){
  # lock succeeded, install signal handlers before storing the PID just in case 
  # storing the PID fails
  trap 'ECODE=$?;
        echo_debug "Removing lock. Exit: ${ETXT[ECODE]}($ECODE)"  >> "$LOGFILE" 2>&1 
        rm -rf "${LOCKDIR}"' 0

  # the following handler will exit the script upon receiving these signals
  # the trap on "0" (EXIT) from above will be triggered by this trap's "exit" command!
  trap 'echo_debug "Killed by signal."  >> "$LOGFILE" 2>&1 
        exit ${ENO_RECVSIG}' 1 2 3 15
}

#___________________________________
function create_random_cryptdev_name() {
  cryptdev=$(cat < /dev/urandom | tr -dc "[:lower:]"  | head -c 8)
}

#___________________________________
function info(){
  echo_debug "LUKS header information for $device"
  echo_debug "Cipher algorithm: ${cipher_algorithm}"
  echo_debug "Hash algorithm ${hash_algorithm}"
  echo_debug "Keysize: ${keysize}"
  echo_debug "Device: ${device}"
  echo_debug "Crypt device: ${cryptdev}"
  echo_debug "Mapper: /dev/mapper/${cryptdev}"
  echo_debug "Mountpoint: ${mountpoint}"
  echo_debug "File system: ${filesystem}"
}

#____________________________________
# Install cryptsetup

function install_cryptsetup(){
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo_info "$ID"
    if [ "$ID" = "ubuntu" ]; then
      echo_info "Distribution: Ubuntu. Using apt."
      apt-get install -y cryptsetup pv
    else
      echo_info "Distribution: CentOS. Using yum."
      yum install -y cryptsetup-luks pv
    fi
  else
    echo_info "Not running a distribution with /etc/os-release available."
  fi
}

#____________________________________
# Check cryptsetup installation

function check_cryptsetup(){
  echo ""
  echo_info "Check if the required applications are installed..."
  type -P dmsetup &>/dev/null || echo_info "dmestup is not installed. Installing..." #TODO add install device_mapper
  type -P cryptsetup &>/dev/null || { echo_info "cryptsetup is not installed. Installing.."; install_cryptsetup >> "$LOGFILE" 2>&1; echo_info "cryptsetup installed."; }
}

#____________________________________
# Check volume 

function check_vol(){
  logs_debug "Checking storage volume."

  if [ $(mount | grep -c $mountpoint) == 1 ]; then

    device=$(df -P $mountpoint | tail -1 | cut -d' ' -f 1)
    logs_debug "Device name: $device"

  elif [ $(mount | grep -c $mountpoint) == 0 ]; then

     if [[ -b $device ]]; then
       logs_debug "External volume on $device. Using it for encryption."
       if [[ ! -d $mountpoint ]]; then
         logs_debug "Creating $mountpoint"
         mkdir -p $mountpoint
         logs_debug "Device name: $device"
         logs_debug "Mountpoint: $mountpoint"
       fi
     else
       logs_error "Device not mounted, exiting!"
       logs_error "Please check logfile: "
       logs_error "No device  mounted to $mountpoint: "
       df -h >> "$LOGFILE" 2>&1
       unlock # unlocking script instance
       exit 1
     fi

  fi

}

#____________________________________
# Check if the volume is already encrypted.
# If yes, skip the encryption

function lsblk_check(){

  logs_debug "Checking if the volume is already encrypted."
  { lsblk -p -o NAME,FSTYPE | grep "$device" | awk '{print $2}' | grep "crypto_LUKS"; } &> /dev/null
  ec_lsblk_check=$?
  if [[ $ec_lsblk_check == 0 ]]; then
    logs_info "The volume is already encrypted."
    return 1
  else
    return 0
  fi

}

#____________________________________
# Umount volume

function umount_vol(){
  logs_info "Umounting device."
  umount $mountpoint >> "$LOGFILE" 2>&1
  logs_info "$device umounted, ready for encryption!"
}

#____________________________________
# Passphrase Random generation
function create_random_secret(){
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $passphrase_length | head -n 1
}

#____________________________________
# Unset sensitive variables
function unset_variables(){
  unset passphrase
  unset passphrase_confirmation
  unset s3cret
}

#____________________________________
function setup_device(){
  echo_info "Start the encryption procedure."
  logs_info "Using $cipher_algorithm algorithm to luksformat the volume."
  logs_debug "Start cryptsetup"
  info >> "$LOGFILE" 2>&1
  logs_debug "Cryptsetup full command:"
  logs_debug "cryptsetup -v --cipher $cipher_algorithm --key-size $keysize --hash $hash_algorithm --iter-time 2000 --use-urandom --verify-passphrase luksFormat $device --batch-mode"

  if $non_interactive; then
    if [ -z "$passphrase_length" ]; then
      if [ -z "$passphrase" ]; then
        echo_error "Missing passphrase!"
        # unset passphrase var
        unset_variables
        unlock
        exit 1
      fi
      if [ -z "$passphrase_confirmation" ]; then
        echo_error "Missing confirmation passphrase!"
        # unset passphrase var
        unset_variables
        unlock
        exit 1
      fi
      if [ "$passphrase" ==  "$passphrase_confirmation" ]; then
        s3cret=$passphrase
      else
        echo_error "No matching passphrases!"
        # unset passphrase var
        unset_variables
        unlock
        exit 1
      fi
    else
      s3cret=$(create_random_secret)
      echo "Your random generated passphrase: $s3cret"
      yum install -y  mailx
      echo " Your random generated passphrase: $s3cret" | /usr/bin/mail -r laniakea@elixir-italy.org -s "[luks] send luks password for testing purporse"  laniakea.testuser@gmail.com
    fi
    #TODO the password can't be longer 512 char
    # Start encryption procedure
    printf "$s3cret\n" | cryptsetup -v --cipher $cipher_algorithm --key-size $keysize --hash $hash_algorithm --iter-time 2000 --use-urandom luksFormat $device --batch-mode
  else
    # Start standard encryption
    cryptsetup -v --cipher $cipher_algorithm --key-size $keysize --hash $hash_algorithm --iter-time 2000 --use-urandom --verify-passphrase luksFormat $device --batch-mode
  fi

  ecode=$?
  if [ $ecode != 0 ]; then
    # Cryptsetup returns 0 on success and a non-zero value on error.
    # Error codes are:
    # 1 wrong parameters
    # 2 no permission (bad passphrase)
    # 3 out of memory
    # 4 wrong device specified
    # 5 device already exists or device is busy.
    logs_error "Command cryptsetup failed with exit code $ecode! Mounting $device to $mountpoint and exiting." #TODO redirect exit code
    if [[ $ecode == 2 ]]; then echo_error "Bad passphrase. Please try again."; fi
    #mount $device $mountpoint
    unlock
    exit $ecode
  fi
}

#____________________________________
function open_device(){
  echo ""
  echo_info "Open LUKS volume."
  if [ ! -b /dev/mapper/${cryptdev} ]; then
    if $non_interactive; then
      printf "$s3cret\n" | cryptsetup luksOpen $device $cryptdev
    else
      cryptsetup luksOpen $device $cryptdev
    fi
    openec=$?
    if [[ $openec != 0 ]]; then
      if [[ $openec == 2 ]]; then echo_error "Bad passphrase. Please try again."; fi
      unlock # unlocking script instance
      exit $openec
    fi
  else
    echo_error "Crypt device already exists! Please check logs: $LOGFILE"
    logs_error "Unable to luksOpen device. "
    logs_error "/dev/mapper/${cryptdev} already exists."
    logs_error "Mounting $device to $mountpoint again."
    mount $device $mountpoint >> "$LOGFILE" 2>&1
    unlock # unlocking script instance
    exit 1
  fi
}

#____________________________________
function encryption_status(){
  echo ""
  logs_info "Check $cryptdev status with cryptsetup status"
  cryptsetup -v status $cryptdev >> "$LOGFILE" 2>&1
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
  echo_info "Paranoid mode selected. Wiping disk."
  logs_info "Wiping disk data by overwriting the entire drive with random data."
  logs_info "This might take time depending on the size & your machine!"

  dd if=/dev/zero of=/dev/mapper/${cryptdev} bs=1M  status=progress
  #{ pv -tpreb /dev/zero | dd of=/dev/mapper/${cryptdev} bs=1M status=progress; } >> "$LOGFILE" 2>&1

  logs_info "Block file /dev/mapper/${cryptdev} created."
  logs_info "Wiping done."
}

#____________________________________
function create_fs(){
  echo_info "Creating filesystem."
  logs_info "Creating ${filesystem} filesystem on /dev/mapper/${cryptdev}"
  mkfs.${filesystem} /dev/mapper/${cryptdev} >> "$LOGFILE" 2>&1 #Do not redirect mkfs, otherwise no interactive mode!
  if [ $? != 0 ]; then
    echo_error "While creating ${filesystem} filesystem. Please check logs: $LOGFILE"
    echo_error "Command mkfs failed!"
    unlock
    exit 1
  fi
}

#____________________________________
function mount_vol(){
  echo_info "Mounting encrypted device."
  logs_info "Mounting /dev/mapper/${cryptdev} to ${mountpoint}"
  mount /dev/mapper/${cryptdev} $mountpoint >> "$LOGFILE" 2>&1
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
  dmsetup info /dev/mapper/${cryptdev} >> "$LOGFILE" 2>&1
  cryptsetup luksDump $device >> "$LOGFILE" 2>&1
}

#____________________________________
function end_encrypt_procedure(){
  # send signal to unclok waiting condition for automation software (e.g Ansible)
  echo "LUKS encryption completed." > $SUCCESS_FILE # WARNING DO NOT MODFIFY THIS LINE, THIS IS A CONTROL STRING FOR ANSIBLE
  echo_info "SUCCESSFUL."
}

#____________________________________
function end_volume_setup_procedure(){
  # send signal to unclok waiting condition for automation software (e.g Ansible)
  echo "Volume setup completed." > $SUCCESS_FILE # WARNING DO NOT MODFIFY THIS LINE, THIS IS A CONTROL STRING FOR ANSIBLE
  echo_info "SUCCESSFUL."
}

#____________________________________
function load_default_config(){
  if [[ -f ./defaults.conf ]]; then
    logs_info "Loading default configuration from defaults.conf"
    source ./defaults.conf
  else
    logs_info "No defaults.conf file found. Loading built-in variables."
    cipher_algorithm='aes-xts-plain64'
    keysize='256'
    hash_algorithm='sha256'
    device='/dev/vdb'
    cryptdev='crypt'
    mountpoint='/export'
    filesystem='ext4'
    paranoid=false
    non_interactive=false
    foreground=false
    luks_cryptdev_file='/tmp/luks-cryptdev.ini'
  fi
}

#____________________________________
# Read ini file
function cfg.parser ()
# http://theoldschooldevops.com/2008/02/09/bash-ini-parser/
{
        IFS=$'\n' && ini=( $(<$1) ) # convert to line-array
        ini=( ${ini[*]//;*/} )      # remove comments with ;
        ini=( ${ini[*]//\#*/} )     # remove comments with #
        ini=( ${ini[*]/\        =/=} )  # remove tabs before =
        ini=( ${ini[*]/=\       /=} )   # remove tabs be =
        ini=( ${ini[*]/\ =\ /=} )   # remove anything with a space around =
        ini=( ${ini[*]/#[/\}$'\n'cfg.section.} ) # set section prefix
        ini=( ${ini[*]/%]/ \(} )    # convert text2function (1)
        ini=( ${ini[*]/=/=\( } )    # convert item to array
        ini=( ${ini[*]/%/ \)} )     # close array parenthesis
        ini=( ${ini[*]/%\\ \)/ \\} ) # the multiline trick
        ini=( ${ini[*]/%\( \)/\(\) \{} ) # convert text2function (2)
        ini=( ${ini[*]/%\} \)/\}} ) # remove extra parenthesis
        ini[0]="" # remove first element
        ini[${#ini[*]} + 1]='}'    # add the last brace
        eval "$(echo "${ini[*]}")" # eval the result
}

function read_ini_file(){

  cfg.parser ${luks_cryptdev_file}
  cfg.section.luks

}
