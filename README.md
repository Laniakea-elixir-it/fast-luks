Fast-LUKS
=========

LUKS (Linux Unified Key Setup) script for Storage encryption development Repository.

Defaults value should not be changed. Changes are reccommended only to experts.

Defaults parameters can be set from command line or changing the defaults.conf file. This is useful with Ansible.

It is mainly made by 5 components:

``fast_luks_encryption.sh``: which is responsible for the encryption.

``fast_luks_volume_setup.sh``: which is in charge of ending volume setup procedure, i.e. format the volume.

``fast_luks.sh``: it is the main script, calling fast_luks_encryption.sh and fast_luks_volume_setup.sh.

``fast_luks_libs.sh``: all the fast_luks function are here.

``defaults.conf``: default configuration file.

After the encryption procedure the script continue running in background using nohup to run the fast_luks_volume_setup.sh script.

The legacy version of this script is in ./legacy directory. The only difference is that the script still run in background, but if the parent process is killed, i.e. the terminal section, it will be killed, too.

Optional arguments
------------------
``-h, --help``: Show help.

``-c, --cipher``: set cipher algorithm [default: aes-xts-plain64].

``-k, --keysize``: set key size [default: 256].

``-a, --hash_algorithm``: set hash algorithm used for key derivation [default: sha256].

``-d, --device``: set device [default: /dev/vdb].

``-e, --cryptdev``: set crypt device [default: cryptdev].

``-m, --mountpoint``: set mount point [default: /export].

``-f, --filesystem``: set filesystem [default: ext4].

``--paranoid-mode``: wipe data after encryption procedure. This take time [default: false].

``--non-interactive``: non-interactive mode, only command line [default: false].

``--foreground``: run script in foreground [default: false].

``--default``: load default values.

Defaults
--------
``cipher_algorithm``: aes-xts-plain64

``keysize``: 256

``hash_algorithm``: sha256

``device``: /dev/vdb

``cryptdev``: crypt [this is randomly generated]

``mountpoint``: /export

``filesystem``: ext4

``paranoid``: false

``non_interactive``: false

``foreground``: false

Usage
-----
```
# ./fast-luks.sh --defaults
```

References
----------
Laniakea documentation: http://laniakea.readthedocs.io

Licence
-------
GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

Credits
-------
Please find the original script here:

https://github.com/JohnTroony/LUKS-OPs/blob/master/luks-ops.sh

All credits to John Troon.

