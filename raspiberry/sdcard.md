### life time cycle of sdcard

sdcard's block has very limited life time [link](https://www.zhihu.com/question/21419030). So, we need to prepare for the broken down time of the sdcard.

[wkikpedia: Wear leveling](https://en.wikipedia.org/wiki/Wear_leveling)


### UBIFS is the soluation

[Choice of filesystem for GNU/Linux on an SD card](https://superuser.com/questions/248078/choice-of-filesystem-for-gnu-linux-on-an-sd-card)

[UBIFS - UBI File-System](http://www.linux-mtd.infradead.org/doc/ubifs.html)


### It's time costing to let UBIFS works
[How to use JFFS2 or UBIFS to avoid data corruption and increase life of the SD card?](https://raspberrypi.stackexchange.com/questions/11932/how-to-use-jffs2-or-ubifs-to-avoid-data-corruption-and-increase-life-of-the-sd-c)


### simple salution

#### use ext2
```
I was facing the same problem and did some research as well. Eventually I decided to go with ext2.

It seems that some SDHC cards implement their own wear-leveling at the hardware layer. If you can get hold of SDHC cards that have wear-leveling buit-in.

Filesystems that provide wear-leveling can interfere with the Flash-level wear-leveling so it can actually be bad for the flash to use them (the IBM article cited above talks about how JFFS does it, so it's clear that that won't work with flash-level WL). I decided I didn't need ext3's journaling since I'm not storing critical data on it and I usually backup regularly anyway (cron).

I also mounted /tmp and /var as tmpfs to speed things up. If you have enough RAM you should do that (but be sure to rotate or delete your logs regularly)

HINT: Mount your ext SD cards with the "noatime" option
```
--- by Khaled at [link](https://superuser.com/questions/248078/choice-of-filesystem-for-gnu-linux-on-an-sd-card)

#### use read only file system such as unionFS
[How to make your Raspberry Pi file system read-only (Raspbian Stretch)](https://medium.com/@andreas.schallwig/how-to-make-your-raspberry-pi-file-system-read-only-raspbian-stretch-80c0f7be7353)

#### ext2 solution

  - disable ext4 journaling [link](https://foxutech.com/how-to-disable-enable-journaling/)
```
tune2fs -O ^has_journal /dev/sda2
e2fsck -f /dev/sda2
```
There is no tune4fs on debian 10, use tune2fs insteed.

  - add `noatime,nodiratime` flag to mount option [link](https://blog.51cto.com/lee90/2376385)
  
  - mount ~/.cache and /tmp as tmpfs
```
tmpfs                   /tmp            tmpfs   mode=1777,nosuid,nodev          0       0
tmpfs                   /root/.cache    tmpfs   mode=1777,nosuid,nodev          0       0
```

#### union mount filesystem
There are btrfs, unionfs, aufs, overlayfs can do this job. By my brief understanding:
- unionfs, original version
- aufs, an advanced version of unionfs. It has lots of mature features rather than overlayfs.
- overlayfs, a simple but included in kernal code tree fs.
- btrfs, I'm not quite understanding what it is. but seems it's a little difference to the other 3 fs. and maybe it's a little old.

some aufs examples:
 - [link1](https://unix.stackexchange.com/questions/27449/mount-a-filesystem-read-only-and-redirect-writes-to-ram)
 - [link2](https://www.thegeekstuff.com/2013/05/linux-aufs/)
 - [link3](https://help.ubuntu.com/community/aufsRootFileSystemOnUsbFlash)
 - [link4](http://chschneider.eu/linux/thin_client/)
 - [link5](https://unix.stackexchange.com/questions/1970/using-a-differencing-aka-overlay-aka-union-file-system-with-commit-capability)
 - [link6](http://aufs.sourceforge.net/)
 - [link7](https://coolshell.cn/articles/17061.html)
 - [link8](https://segmentfault.com/a/1190000008489207)
 - [link9](http://manpages.ubuntu.com/manpages/xenial/en/man5/aufs.5.html)
 - [link10](https://www.srijn.net/read-only-root-on-linux/)
Personaly, I'd like to try aufs. Unfortunatly, raspbian seems not work with aufs unless compile kernal manually. For a lazy person, of course I've gave up.


## My Solution
 - make the sdcard to 4 partitition
    - sda1 is boot partition, vfat
    - sda2 is for /, ext4, but disable journal logs. ```mkfs.ext4 -O ^has_journal /dev/sda2```, this parititon is read only
    - sda3 is for /var and app, data. ext4, but disable journal logs.
    - sda4 is for future usage. ext4, but disable journal logs.
 - fstab
```
proc                    /proc           proc    defaults                        0       0
/dev/sda1               /boot           vfat    ro,defaults                     0       2
/dev/sda2               /               ext4    ro,defaults                     0       1
/dev/sda4               /backup         ext4    defaults,noatime,nodiratime     0       1

tmpfs                   /tmp            tmpfs   mode=1777,nosuid,nodev          0       0
tmpfs                   /root/.cache    tmpfs   mode=1777,nosuid,nodev          0       0
tmpfs                   /cache          tmpfs   mode=1777,nosuid,nodev          0       0

```
we need to let the /cache and /writable is mount first, then the /var the /opt, refer this link to set mount order. [link1](https://askubuntu.com/questions/40185/how-can-i-specify-the-order-in-which-filesystems-are-automatically-mounted) [link2](https://github.com/systemd/systemd/commit/3519d230c8bafe834b2dac26ace49fcfba139823)

 - run a systemd script before all the others partittion's mount, just after /
```
        mkdir -p /cache
        mount -t tmpfs /cache

        # mount disk partitiion3 to /writable
        mount -t ext4 -o noatime,nodiratime /dev/mmcblk0p3 /writable/

        # create overlay mount dir
        mkdir -p /cache/var /cache/opt /cache/overlay/var /cache/overlay/opt
        mkdir -p /writable/var /writable/opt

        # mount /var
        mount -t overlay overlay -o lowerdir=/writable/var:/var_bak,upperdir=/cache/var,workdir=/cache/overlay/var /var

        # mount /opt
        mount -t overlay overlay -o lowerdir=/writable/opt,upperdir=/cache/opt,workdir=/cache/overlay/opt /opt
```
 - register to the systemd service
```
[Unit]
Description=Mount /var and /opt by overlay
Requires=syslog.socket

[Service]
User=root
WorkingDirectory=/etc/init.d
ExecStart=/etc/init.d/tmpfs_overlay.sh
Restart=always
Before=basic.target

[Install]
WantedBy=multi-user.target
Alias=tmpfs_overlay.service
```

- move docker is another challenge
   - [link](https://jimfrenette.com/docker/relocate-docker-runtime-and-storage/)
   - 

For details, refer to the [system/raspiberry/etc](https://github.com/marcusyh/system/tree/master/raspiberry/etc)

- even though the root parition was set to readonly, it's still have a possibility to crush, so, backup is a must.
- to backup:
   - backup the [MBR](https://en.wikipedia.org/wiki/Master_boot_record) by `dd if=/dev/sda of=0_445_mbr_446 bs=446 count=1`
   - backup from the 510Bytes to 8191 Bytes, (I don't know why these area is not used by any paritition on my sdcard) `dd if=/dev/sda of=510_8191_space_7682 bs=7682 skip=510 count=1`
   - backup /dev/sda1, the boot paritition `dd if=/dev/sda1 of=dev_sd1_boot_partition`
   - backup /, rsync is better
- to restore
   - restore MBR `dd if=0_445_mbr_446 of=/dev/sda bs=446 count=1`
   - restore the skipped area `dd if=510_8191_space_7682 of=/dev/sda seek=510 bs=7682 count=1`
   - retore dd if=/data/realtime/router/510_8191_space_7682 of=/dev/sda seek=510 bs=7682 count=1
   - restore the boot paritition `dd if=dev_sd1_boot_partition of=/dev/sda1`
- the difference of skip and seek parameter of dd. [link1](https://unix.stackexchange.com/questions/252509/using-dd-in-order-to-save-and-restore-a-boot-sector) [link2](https://unix.stackexchange.com/questions/307186/what-is-the-difference-between-seek-and-skip-in-dd-command)


