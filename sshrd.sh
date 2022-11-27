#!/usr/bin/env sh

set -e

oscheck=$(uname)
arch=$(uname -m)
if [ "$oscheck" = "Linux" ]; then
    dir="$(pwd)/Linux/$arch"
else
    dir="$(pwd)/Darwin"
fi

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

if [ ! -e "$dir"/gaster ]; then
    if [ "$oscheck" = 'Linux' ]; then
        extrapath="-${arch}"
    fi
    curl -sLO https://nightly.link/palera1n/gaster/workflows/makefile/main/gaster-"$oscheck$extrapath".zip
    unzip gaster-"$oscheck$extrapath".zip
    mv gaster "$dir"/
    rm -rf gaster gaster-"$oscheck$extrapath".zip
fi

chmod +x "$dir"/*

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

check=$("$dir"/irecovery -q | grep CPID | sed 's/CPID: //')
replace=$("$dir"/irecovery -q | grep MODEL | sed 's/MODEL: //')
deviceid=$("$dir"/irecovery -q | grep PRODUCT | sed 's/PRODUCT: //')
ipswurl=$(curl -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$dir"/jq '.firmwares | .[] | select(.version=="'$1'")' | "$dir"/jq -s '.[0] | .url' --raw-output)

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

    "$dir"/gaster pwn
    sleep 1
    "$dir"/gaster reset
    sleep 1
    "$dir"/irecovery -f sshramdisk/iBSS.img4
    sleep 2
    "$dir"/irecovery -f sshramdisk/iBEC.img4
    if [ "$check" = '0x8010' ] || [ "$check" = '0x8015' ] || [ "$check" = '0x8011' ] || [ "$check" = '0x8012' ]; then
        sleep 1
        "$dir"/irecovery -c go
    fi
    sleep 1
    "$dir"/irecovery -f sshramdisk/bootlogo.img4
    sleep 1
    "$dir"/irecovery -c "setpicture 0x1"
    sleep 1
    "$dir"/irecovery -f sshramdisk/ramdisk.img4
    sleep 1
    "$dir"/irecovery -c ramdisk
    sleep 1
    "$dir"/irecovery -f sshramdisk/devicetree.img4
    sleep 1
    "$dir"/irecovery -c devicetree
    sleep 1
    "$dir"/irecovery -f sshramdisk/trustcache.img4
    sleep 1
    "$dir"/irecovery -c firmware
    sleep 1
    "$dir"/irecovery -f sshramdisk/kernelcache.img4
    sleep 1
    "$dir"/irecovery -c bootx

    exit
fi

if [ -z "$1" ]; then
    printf "1st argument: iOS version for the ramdisk\n"
    exit
fi

if [ ! -e work ]; then
    mkdir work
fi

"$dir"/gaster pwn
"$dir"/img4tool -e -s shsh/"${check}".shsh -m work/IM4M

cd work
"$dir"/pzb -g BuildManifest.plist "$ipswurl"
"$dir"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"
"$dir"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"
"$dir"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/DeviceTree[.]/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"

if [ "$oscheck" = 'Darwin' ]; then
    "$dir"/pzb -g Firmware/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)".trustcache "$ipswurl"
else
    "$dir"/pzb -g Firmware/"$("$dir"/PlistBuddy BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')".trustcache "$ipswurl"
fi

"$dir"/pzb -g "$(awk "/""${replace}""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" "$ipswurl"

if [ "$oscheck" = 'Darwin' ]; then
    "$dir"/pzb -g "$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" "$ipswurl"
else
    "$dir"/pzb -g "$("$dir"/PlistBuddy BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')" "$ipswurl"
fi

cd ..
"$dir"/gaster decrypt work/"$(awk "/""${replace}""/{x=1}x&&/iBSS[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')" work/iBSS.dec
"$dir"/gaster decrypt work/"$(awk "/""${replace}""/{x=1}x&&/iBEC[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')" work/iBEC.dec
"$dir"/iBoot64Patcher work/iBSS.dec work/iBSS.patched
python3 -m pyimg4 im4p create -i work/iBSS.patched -o work/iBSS.patched.im4p -f ibss
python3 -m pyimg4 img4 create -p work/iBSS.patched.im4p -m work/IM4M -o sshramdisk/iBSS.img4
"$dir"/iBoot64Patcher work/iBEC.dec work/iBEC.patched -b "rd=md0 debug=0x2014e wdt=-1 `if [ -z "$2" ]; then :; else echo "$2=$3"; fi` `if [ "$check" = '0x8960' ] || [ "$check" = '0x7000' ] || [ "$check" = '0x7001' ]; then echo "-restore"; fi`" -n
python3 -m pyimg4 im4p create -i work/iBEC.patched -o work/iBEC.patched.im4p -f ibec
python3 -m pyimg4 img4 create -p work/iBEC.patched.im4p -m work/IM4M -o sshramdisk/iBEC.img4

python3 -m pyimg4 im4p extract -i work/"$(awk "/""${replace}""/{x=1}x&&/kernelcache.release/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1)" -o work/kcache.raw
"$dir"/Kernel64Patcher work/kcache.raw work/kcache.patched -a
python3 -m pyimg4 im4p create -i work/kcache.patched -o work/kernelcache.im4p -f rkrn `if [ "$oscheck" = 'Linux' ]; then echo "--lzss"; fi`
python3 -m pyimg4 img4 create -p work/kernelcache.im4p -m work/IM4M -o sshramdisk/kernelcache.img4
python3 -m pyimg4 im4p create -i work/"$(awk "/""${replace}""/{x=1}x&&/DeviceTree[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]//')" -o work/devicetree.im4p -f rdtr
python3 -m pyimg4 img4 create -p work/devicetree.im4p -m work/IM4M -o sshramdisk/devicetree.img4
if [ "$oscheck" = 'Darwin' ]; then
    python3 -m pyimg4 im4p create -i work/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)".trustcache -o work/trustcache.im4p -f rtsc
    python3 -m pyimg4 img4 create -p work/trustcache.im4p -m work/IM4M -o sshramdisk/trustcache.img4
    python3 -m pyimg4 im4p extract -i work/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."RestoreRamDisk"."Info"."Path" xml1 -o - work/BuildManifest.plist | grep '<string>' |cut -d\> -f2 |cut -d\< -f1 | head -1)" -o work/ramdisk.dmg
else
    python3 -m pyimg4 im4p create -i work/"$("$dir"/PlistBuddy work/BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')".trustcache -o work/trustcache.im4p -f rtsc
    python3 -m pyimg4 img4 create -p work/trustcache.im4p -m work/IM4M -o sshramdisk/trustcache.img4
    python3 -m pyimg4 im4p extract -i work/"$("$dir"/PlistBuddy work/BuildManifest.plist -c "Print BuildIdentities:0:Manifest:RestoreRamDisk:Info:Path" | sed 's/"//g')" -o work/ramdisk.dmg
fi

if [ "$oscheck" = 'Darwin' ]; then
    hdiutil resize -size 256MB work/ramdisk.dmg
    hdiutil attach -mountpoint /tmp/SSHRD work/ramdisk.dmg

    "$dir"/gtar -x --no-overwrite-dir -f other/ramdisk.tar.gz -C /tmp/SSHRD/

    if [ ! "$2" = 'rootless' ]; then
        curl -LO https://nightly.link/elihwyma/Pogo/workflows/build/root/Pogo.zip
        mv Pogo.zip work/Pogo.zip
        unzip work/Pogo.zip -d work/Pogo
        unzip work/Pogo/Pogo.ipa -d work/Pogo/Pogo
        rm -rf /tmp/SSHRD/usr/local/bin/loader.app/*
        cp -R work/Pogo/Pogo/Payload/Pogo.app/* /tmp/SSHRD/usr/local/bin/loader.app
        mv /tmp/SSHRD/usr/local/bin/loader.app/Pogo /tmp/SSHRD/usr/local/bin/loader.app/Tips
    fi

    hdiutil detach -force /tmp/SSHRD
    hdiutil resize -sectors min work/ramdisk.dmg
else
    if [ -f other/ramdisk.tar.gz ]; then
        gzip -d other/ramdisk.tar.gz
    fi

    "$dir"/hfsplus work/ramdisk.dmg grow 300000000 > /dev/null
    "$dir"/hfsplus work/ramdisk.dmg untar other/ramdisk.tar > /dev/null

    if [ ! "$2" = 'rootless' ]; then
        curl -LO https://nightly.link/elihwyma/Pogo/workflows/build/root/Pogo.zip
        mv Pogo.zip work/Pogo.zip
        unzip work/Pogo.zip -d work/Pogo
        unzip work/Pogo/Pogo.ipa -d work/Pogo/Pogo
        mkdir -p work/Pogo/uwu/usr/local/bin/loader.app
        cp -R work/Pogo/Pogo/Payload/Pogo.app/* work/Pogo/uwu/usr/local/bin/loader.app

        "$dir"/hfsplus work/ramdisk.dmg rmall usr/local/bin/loader.app > /dev/null
        "$dir"/hfsplus work/ramdisk.dmg addall work/Pogo/uwu > /dev/null
        "$dir"/hfsplus work/ramdisk.dmg mv /usr/local/bin/loader.app/Pogo /usr/local/bin/loader.app/Tips > /dev/null
    fi
fi
python3 -m pyimg4 im4p create -i work/ramdisk.dmg -o work/ramdisk.im4p -f rdsk
python3 -m pyimg4 img4 create -p work/ramdisk.im4p -m work/IM4M -o sshramdisk/ramdisk.img4
python3 -m pyimg4 img4 create -p other/bootlogo.im4p -m work/IM4M -o sshramdisk/bootlogo.img4

rm -rf work
