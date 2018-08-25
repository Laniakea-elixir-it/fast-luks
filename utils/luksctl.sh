#!/bin/bash

# LUKS central management tool
# This script requires dmsetup and cryptsetup.
# Needs to be launched as superuser.
#
# Author: Marco Tangaro
# mail: ma.tangaro@ibiom.cnr.it
# CNR-IBIOM, ELIXIR-ITALY
# 
# LICENCE: BSD

cryptdev_ini_file='/tmp/luks-cryptdev.ini'

#____________________________________
# Script needs superuser

function __su_check(){
  if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo -e "[Error] Not running as root."
    exit
 fi
}

#____________________________________
# Display dmsetup info

function __dmsetup_info(){
  dmsetup info /dev/mapper/$cryptdev
}

#____________________________________
# check encrypted storage mounted
function __cryptdev_status(){

  # check if $mountpoint is a mount point
  mountpoint $mountpoint &> /dev/null
  if [ $? -ne 0 ]; then
    echo -e "\n${mountpoint} is not a mount point."
    exit 1
  fi

  # if $mountpoint is a mount point 
  __dmsetup_info &>/dev/null

  echo 'LUKS volume configuration'
  echo 'Cipher algorithm:' $cipher_algorithm
  echo 'Hash algorithm:' $hash_algorithm
  echo 'Key size:' $keysize
  echo 'Device:' $device
  echo 'UUID:' $uuid
  echo 'Crypt device:' $cryptdev
  echo 'Mapper:' $mapper
  echo 'Mount point:' $mountpoint
  echo 'File system:' $filesystem

  if [ $? -eq 0 ]; then
    echo -e "\nEncrypted volume: [ OK ]"
  else
    echo -e "\nEncrypted volume: [ FAIL ]"
  fi
}

#____________________________________
# luksOpen device

function __luksopen_cryptdev(){
  cryptsetup luksOpen /dev/disk/by-uuid/$uuid $cryptdev
  dmsetup info /dev/mapper/$cryptdev
  mount /dev/mapper/$cryptdev $mountpoint
  code=$?
  if [ "$code" -ne 0 ]; then
    return 31 # return error code 0
  else 
    return 0 # return success
  fi
}

#____________________________________
# Open encrypted device

function __cryptdev_open(){
  __luksopen_cryptdev
  code=$?
  if [ "$code" -eq "0" ]; then
    __cryptdev_status
  else
    echo -e "\nEncrypted volume mount: [ FAIL ]"
  fi
}

#____________________________________
# luksClose device 

function __luksclose_cryptdev(){
  umount $mountpoint
  cryptsetup close $cryptdev
}

#____________________________________
# Close encrypted device

function __cryptdev_close(){
  __luksclose_cryptdev
  __dmsetup_info &>/dev/null
  if [ $? -eq 0 ]; then
    echo -e "\nEncrypted volume umount: [ FAIL ]"
  else
    echo -e "\nEncrypted volume umount: [ OK ]"
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
	ini=( ${ini[*]/\	=/=} )  # remove tabs before =
	ini=( ${ini[*]/=\	/=} )   # remove tabs be =
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

  cfg.parser $cryptdev_ini_file
  cfg.section.luks

}

#____________________________________
# Show help

function __cryptdev_help(){
  echo -e "\nUsage: galaxyctl luks <option>"
  echo -e "\nEncrypted volume options:\n"
  echo -e "  --help [print-out cryptdevice options]\n"
  echo -e '  open [luks open and mount volume]\n'
  echo -e '  close [luks close and umount volume]\n'
  echo -e '  status [check volume status]\n'
}

#____________________________________
# Cryptdevice options

if [[ $1 == '--help' ]]; then __cryptdev_help; fi

__su_check

read_ini_file

if [[ $# -gt 0 ]]; then
  if [ "$1" == 'open' ]; then __cryptdev_open; fi
  if [ "$1" == 'close' ]; then __cryptdev_close; fi
  if [ "$1" == 'status' ]; then __cryptdev_status; fi
fi
