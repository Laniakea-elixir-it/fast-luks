Fast-LUKS
=========

LUKS (Linux Unified Key Setup) script for Storage encryption Repository


Defaults
--------

Optional arguments
------------------
``-h, --help``: Show help
``-c, --cipher                 \t\tset cipher algorithm [default: aes-xts-plain64]\n
``-k, --keysize                \t\tset key size [default: 256]\n
``-a, --hash_algorithm         \tset hash algorithm used for key derivation\n
``-d, --device                 \t\tset device [default: /dev/vdb]\n
``-e, --cryptdev               \tset crypt device [default: cryptdev]\n
``-m, --mountpoint             \tset mount point [default: /export]\n
``-f, --filesystem             \tset filesystem [default: ext4]\n
``--paranoid-mode              \twipe data after encryption procedure. This take time [default: false]\n
``--non-interactive            \tnon-interactive mode, only command line [default: false]\n
          --foregroun                  \t\trun script in foreground [default: false]\n
           --default                    \t\tload default values\n"

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
