Fast-LUKS
=========

LUKS (Linux Unified Key Setup) script for Storage encryption Repository


Defaults
--------

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

Usage
-----

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
