# Build ImmortalWrt for Ruijie X30E Pro
Source code to use: https://github.com/chasey-dev/immortalwrt-mt798x-rebase  
Build ImmortalWrt using GitHub Actions.
<br><br>

## Build Steps
Install requirements for Ubuntu 24.04
```bash
sudo apt update

sudo apt install -y build-essential clang flex bison g++ gawk \
gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
python3-setuptools rsync swig unzip zlib1g-dev file wget curl
```
Clone the source code
```bash
git clone -b 25.12 --single-branch --filter=blob:none \
https://github.com/chasey-dev/immortalwrt-mt798x-rebase.git immortalwrt

cd immortalwrt
```
Update the feeds
```bash
./scripts/feeds update -a
./scripts/feeds install -a
```
Configure the build
```bash
cp ../defconfig/mt7981-ruijie-x30e-pro_defconfig .config
make defconfig
```
Build the firmware
```bash
make -j$(nproc) V=s
```
The firmware will be located in `bin/targets/mediatek/filogic/`.  
<br>
Use the [hanwckf's u-boot](https://github.com/hanwckf/bl-mt798x) or [yuzhii's variant](https://github.com/Yuzhii0718/bl-mt798x-dhcpd) to flash the factory firmware.
<br><br>
