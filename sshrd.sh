#!/usr/bin/env bash

set -e

oscheck=$(uname)

ERR_HANDLER () {
    [ $? -eq 0 ] && exit
    echo "[-] An error occurred"
    rm -rf work
}

trap ERR_HANDLER EXIT

# Check for pyimg4
if ! python3 -c 'import pkgutil; exit(not pkgutil.find_loader("pyimg4"))'; then
    echo '[-] pyimg4 not installed. Press any key to install it, or press ctrl + c to cancel'
    read -n 1 -s
    python3 -m pip install pyimg4
fi

# git submodule update --init --recursive

if [ ! -e "$oscheck"/gaster ]; then
    curl -sLO https://static.palera.in/deps/gaster-"$oscheck".zip
    unzip gaster-"$oscheck".zip
    mv gaster "$oscheck"/
    rm -rf gaster gaster-"$oscheck".zip
fi

chmod +x "$oscheck"/*

if [ "$oscheck" = 'Darwin' ]; then
    if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); then
        echo "[*] Waiting for device in DFU mode"
    fi
    
    while ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode)' >> /dev/null); do
        sleep 1
    done
else
    if ! (lsusb 2> /dev/null | grep ' Apple, Inc. Mobile Device (DFU Mode)' >> /dev/null); then
        echo "[*] Waiting for device in DFU mode"
    fi
    
    while ! (lsusb 2> /dev/null | grep ' Apple, Inc. Mobile Device (DFU Mode)' >> /dev/null); do
        sleep 1
    done
fi

check=$("$oscheck"/irecovery -q | grep CPID | sed 's/CPID: //')
replace=$("$oscheck"/irecovery -q | grep MODEL | sed 's/MODEL: //')
deviceid=$("$oscheck"/irecovery -q | grep PRODUCT | sed 's/PRODUCT: //')

if [ -e work ]; then
    rm -rf work
fi

if [ ! -e sshramdisk ]; then
    mkdir sshramdisk
fi

if [ "$1" = 'boot' ]; then
    if [ ! -e sshramdisk/iBSS.img4 ]; then
        echo "[-] Please create an SSH ramdisk first!"
        exit
    fi

    "$oscheck"/gaster pwn
    sleep 1
    "$oscheck"/gaster reset
    sleep 1
    "$oscheck"/irecovery -f sshramdisk/iBSS.img4
    sleep 2
    "$oscheck"/irecovery -f sshramdisk/iBEC.img4
    if [ "$check" = '0x8010' ] || [ "$check" = '0x8015' ] || [ "$check" = '0x8011' ] || [ "$check" = '0x8012' ]; then
        sleep 1
        "$oscheck"/irecovery -c go
    fi
    sleep 1
    "$oscheck"/irecovery -f sshramdisk/bootlogo.img4
    sleep 1
    "$oscheck"/irecovery -c "setpicture 0x1"
    sleep 1
    "$oscheck"/irecovery -f sshramdisk/ramdisk.img4
    sleep 1
    "$oscheck"/irecovery -c ramdisk
    sleep 1
    "$oscheck"/irecovery -f sshramdisk/devicetree.img4
    sleep 1
    "$oscheck"/irecovery -c devicetree
    sleep 1
    "$oscheck"/irecovery -f sshramdisk/trustcache.img4
    sleep 1
    "$oscheck"/irecovery -c firmware
    sleep 1
    "$oscheck"/irecovery -f sshramdisk/kernelcache.img4
    sleep 1
    "$oscheck"/irecovery -c bootx

    exit
fi

if [ -z "$1" ]; then
    printf "1st argument: iOS version for the ramdisk\n"
    exit
fi

if [ ! -e work ]; then
    mkdir work
fi

if [[ "$deviceid" == *"iPad"* ]] && [[ "$1" == *"16"* ]]; then
    ipswurl=$(curl -sL https://api.appledb.dev/ios/iPadOS\;20A5349b.json | "$oscheck"/jq -r .devices\[\"$deviceid\"\].ipsw)
else
    if [[ "$deviceid" == *"iPad"* ]]; then
        device_os=iPadOS
        device=iPad
    elif [[ "$deviceid" == *"iPod"* ]]; then
        device_os=iOS
        device=iPod
    else
        device_os=iOS
        device=iPhone
    fi

    buildid=$(curl -sL https://api.ipsw.me/v4/ipsw/$1 | "$oscheck"/jq '[.[] | select(.identifier | startswith("'$device'")) | .buildid][0]' --raw-output)
    if [ "$buildid" == "19B75" ]; then
        buildid=19B74
    fi
    ipswurl=$(curl -sL https://api.appledb.dev/ios/$device_os\;$buildid.json | "$oscheck"/jq -r .devices\[\"$deviceid\"\].ipsw)
fi

"$oscheck"/gaster pwn
cp aptickets/$check.der work/IM4M

cd work
../"$oscheck"/pzb -g BuildManifest.plist "$ipswurl"
../"$oscheck"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"
../"$oscheck"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"
../"$oscheck"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/DeviceTree[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"

if [ "$oscheck" = 'Darwin' ]; then
    ../"$oscheck"/pzb -g Firmware/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)".trustcache "$ipswurl"
else
    ../"$oscheck"/pzb -g Firmware/"$(../Linux/PlistBuddy BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')".trustcache "$ipswurl"
fi

../"$oscheck"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"

if [ "$oscheck" = 'Darwin' ]; then
    ../"$oscheck"/pzb -g "$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" "$ipswurl"
else
    ../"$oscheck"/pzb -g "$(../Linux/PlistBuddy BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')" "$ipswurl"
fi

cd ..
"$oscheck"/gaster decrypt work/"$(awk "/""${replace}""/{x=1}x&&/iBSS[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')" work/iBSS.dec
"$oscheck"/gaster decrypt work/"$(awk "/""${replace}""/{x=1}x&&/iBEC[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')" work/iBEC.dec
"$oscheck"/iBoot64Patcher work/iBSS.dec work/iBSS.patched
python3 -m pyimg4 im4p create -i work/iBSS.patched -o work/iBSS.im4p -f ibss
python3 -m pyimg4 img4 create -p work/iBSS.im4p -m work/IM4M -o sshramdisk/iBSS.img4
"$oscheck"/iBoot64Patcher work/iBEC.dec work/iBEC.patched -b "rd=md0 debug=0x2014e wdt=-1 serial=3 `if [ "$check" = '0x8960' ] || [ "$check" = '0x7000' ] || [ "$check" = '0x7001' ]; then echo "-restore"; fi`" -n
python3 -m pyimg4 im4p create -i work/iBEC.patched -o work/iBEC.im4p -f ibec
python3 -m pyimg4 img4 create -p work/iBEC.im4p -m work/IM4M -o sshramdisk/iBEC.img4

python3 -m pyimg4 im4p extract -i work/"$(awk "/""${replace}""/{x=1}x&&/kernelcache.release/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" -o work/kcache.raw
"$oscheck"/Kernel64Patcher work/kcache.raw work/kcache.patched -a
python3 -m pyimg4 im4p create -i work/kcache.patched -o work/kcache.im4p -f rkrn --lzss
python3 -m pyimg4 img4 create -p work/kcache.im4p -m work/IM4M -o sshramdisk/kernelcache.img4

python3 -m pyimg4 im4p extract -i work/"$(awk "/""${replace}""/{x=1}x&&/DeviceTree[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]//')" -o work/dtree.raw --no-decompress
python3 -m pyimg4 im4p create -i work/dtree.raw -o work/dtree.im4p -f rdtr
python3 -m pyimg4 img4 create -p work/dtree.im4p -m work/IM4M -o sshramdisk/devicetree.img4

if [ "$oscheck" = 'Darwin' ]; then
    python3 -m pyimg4 im4p extract -i work/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)".trustcache -o work/trustcache
    python3 -m pyimg4 im4p create -i work/trustcache -o work/trustcache.im4p -f rtsc
    python3 -m pyimg4 img4 create -p work/trustcache.im4p -m work/IM4M -o sshramdisk/trustcache.img4

    python3 -m pyimg4 im4p extract -i work/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" -o work/ramdisk.dmg
else
    python3 -m pyimg4 im4p extract -i work/"$(Linux/PlistBuddy work/BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')".trustcache -o work/trustcache
    python3 -m pyimg4 im4p create -i work/trustcache -o work/trustcache.im4p -f rtsc
    python3 -m pyimg4 img4 create -p work/trustcache.im4p -m work/IM4M -o sshramdisk/trustcache.img4

    python3 -m pyimg4 im4p extract -i work/"$(Linux/PlistBuddy work/BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')" -o work/ramdisk.dmg
fi

if [ "$oscheck" = 'Darwin' ]; then
    hdiutil resize -size 256MB work/ramdisk.dmg
    hdiutil attach -mountpoint /tmp/SSHRD work/ramdisk.dmg

    "$oscheck"/gtar -x --no-overwrite-dir -f other/ramdisk.tar.gz -C /tmp/SSHRD/

    #if [ ! "$2" = 'rootless' ]; then
    #    curl -LO https://nightly.link/elihwyma/Pogo/workflows/build/root/Pogo.zip
    #    mv Pogo.zip work/Pogo.zip
    #    unzip work/Pogo.zip -d work/Pogo
    #    unzip work/Pogo/Pogo.ipa -d work/Pogo/Pogo
    #    rm -rf /tmp/SSHRD/usr/local/bin/loader.app/*
    #    cp -R work/Pogo/Pogo/Payload/Pogo.app/* /tmp/SSHRD/usr/local/bin/loader.app
    #    mv /tmp/SSHRD/usr/local/bin/loader.app/Pogo /tmp/SSHRD/usr/local/bin/loader.app/Tips
    #fi

    hdiutil detach -force /tmp/SSHRD
    hdiutil resize -sectors min work/ramdisk.dmg
else
    if [ -f other/ramdisk.tar.gz ]; then
        gzip -f -k -d other/ramdisk.tar.gz
    fi

    "$oscheck"/hfsplus work/ramdisk.dmg grow 300000000 > /dev/null
    "$oscheck"/hfsplus work/ramdisk.dmg untar other/ramdisk.tar > /dev/null

    #if [ ! "$2" = 'rootless' ]; then
    #    curl -LO https://nightly.link/elihwyma/Pogo/workflows/build/root/Pogo.zip
    #    mv Pogo.zip work/Pogo.zip
    #    unzip work/Pogo.zip -d work/Pogo
    #    unzip work/Pogo/Pogo.ipa -d work/Pogo/Pogo
    #    mkdir -p work/Pogo/uwu/usr/local/bin/loader.app
    #    cp -R work/Pogo/Pogo/Payload/Pogo.app/* work/Pogo/uwu/usr/local/bin/loader.app

    #    "$oscheck"/hfsplus work/ramdisk.dmg rmall usr/local/bin/loader.app > /dev/null
    #    "$oscheck"/hfsplus work/ramdisk.dmg addall work/Pogo/uwu > /dev/null
    #    "$oscheck"/hfsplus work/ramdisk.dmg mv /usr/local/bin/loader.app/Pogo /usr/local/bin/loader.app/Tips > /dev/null
    #fi
fi
python3 -m pyimg4 im4p create -i work/ramdisk.dmg -o work/ramdisk.im4p -f rdsk
python3 -m pyimg4 img4 create -p work/ramdisk.im4p -m work/IM4M -o sshramdisk/ramdisk.img4
python3 -m pyimg4 im4p create -i other/bootlogo.raw -o work/bootlogo.im4p -f rlgo
python3 -m pyimg4 img4 create -p work/bootlogo.im4p -m work/IM4M -o sshramdisk/bootlogo.img4

rm -rf work
