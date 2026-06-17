#! /bin/bash
set -eu
#set -x


variant=${variant:-immortalwrt}
variant=${variant,,}
openwrtver=${openwrtver:-snapshot}
openwrtver=${openwrtver,,}

model=${model:-x60-new-ubi}
model=${model,,}
vendor=${vendor:-ruijie}
vendor=${vendor,,}
device=${vendor}_rg-${model}

platform=${platform:-mediatek}
subtarget=${subtarget:-filogic}

pkgadd=${pkgadd:-}
pkgremove=${pkgremove:-}

firmwarenm=${variant}-${openwrtver}-${model}-squashfs-sysupgrade

initkernelsrc=mediatek-filogic-openwrt_one-initramfs.itb
initramfsdtb=image-*-${model}_initramfs.dtb
initramfsnm=${variant}-${openwrtver}-${model}-initramfs

cd $(dirname "$0")
rootpath="$(pwd)"

builder_site=https://downloads.${variant}.org



## download imagebuilder
if [ ${openwrtver} = "snapshot" ]; then
  downloadurl=${builder_site}/snapshots/targets/${platform}/${subtarget}/${variant}-imagebuilder-${platform}-${subtarget}.Linux-x86_64.tar.zst
else
  downloadurl=${builder_site}/releases/${openwrtver}/targets/${platform}/${subtarget}/${variant}-imagebuilder-${openwrtver}-${platform}-${subtarget}.Linux-x86_64.tar.zst
fi

if [ ! -d builder ]; then
  echo "download imagebuilder..."
	wget -O - ${downloadurl} | tar --zstd -xf - 
	mv *imagebuilder*-x86_64 builder
fi

cd builder

## add build target
echo -e "\nadd build target into makefile..."
modeldir=${rootpath}/${model}
makefile=target/linux/${platform}/image/${subtarget}.mk
sed "/${device}/,/${device}/d" -i ${makefile}
cat ${modeldir}/${model}.mk >> ${makefile}


## add board profile
echo -e "\nadd board profile into .targetinfo"
prof=.targetinfo
sed "/Target-Profile: DEVICE_${device}/,/@@/d" -i ${prof}

export profile=$(sed ':a; /\\$/ { N; s/\\\n//; ba }' ${modeldir}/${model}.mk | awk '
BEGIN {
    has_meta = 0
    pkg = ""
}
/:=/ {
    k = $1; v = $0;
    sub(/^.*:=/, "", v);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", k);
    gsub(/[[:space:]]+/, " ", v);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);

    if (k == "DEVICE_VENDOR") vendor = v;
    if (k == "DEVICE_MODEL") model = v;
    if (k == "DEVICE_PACKAGES") pkg = v;
}
/append-metadata/ { has_meta = 1 }
END {
    vendorl = tolower(vendor)
    modell = tolower(model)
    gsub(/[()]/, "", modell)
    gsub(" ", "-", modell)
    printf "\nTarget-Profile: DEVICE_%s_%s\n", vendorl, modell
    printf "Target-Profile-Name: %s %s\n", vendor, model
    printf "Target-Profile-Packages: %s \n", pkg
    printf "Target-Profile-hasImageMetadata: %d\n", has_meta
    printf "Target-Profile-SupportedDevices: %s,%s\n\n\n", vendorl, modell
    printf "Target-Profile-Description:\n"
    printf "Build firmware images for %s %s\n\n\n\n\n\n@@\n", vendor, model
}')

awk -v p="Target: ${platform}/${subtarget}" \
' $0 == p {found=1; count=0} 
  found && /@@/ {count++} 1; 
  count==2 {print ENVIRON["profile"]; count=0; found=0}
' ${prof} > ${prof}.tmp && mv ${prof}.tmp ${prof}


## add files to include
echo -e "\nadd custom files..."
[ -d files ] && rm -rf files || true
cp -rf ${rootpath}/files .


## copy dtb to build dir
echo -e "\ncopy dtb to build dir..."
kerneldir=${rootpath}/builder/build_dir/target-aarch64_cortex-a53_musl/linux-${platform}_${subtarget}
cp ${modeldir}/image-*-${model}.dtb ${kerneldir}/


## create kernel.bin
echo -e "\ncreate kernel.bin..."
hostbindir=${rootpath}/builder/staging_dir/host/bin
kernelfile=${kerneldir}/${device}-kernel.bin
[ -e ${kernelfile} ] && rm -f ${kernelfile} || true
${hostbindir}/gzip -f -9 -n -c $kerneldir/Image > ${kernelfile}


## prepare output dir
[ -d _output ] && rm -rf _output || true
mkdir _output
outdir=${rootpath}/builder/_output


## build sysupgrade.itb
echo -e "\nbuild sysupgrade.itb..."
[[ "$pkgremove" ]] && ! $(echo "$pkgremove" | grep -q '-') && \
pkgremove=$(echo "$pkgremove" | sed "s/ / -/g; s/^/-/")

make image \
PROFILE="${device}" \
FILES="files" \
BIN_DIR="${outdir}" \
PACKAGES="${pkgadd} ${pkgremove}"


## create initramfs.itb
echo -e "\nprepare initrd..."
initrddir=${rootpath}/builder/build_dir/target-aarch64_cortex-a53_musl/root-mediatek
cp -fpR ${rootpath}/builder/target/linux/generic/other-files/init ${initrddir}/
(cd ${initrddir}; find . | LC_ALL=C sort | ${hostbindir}/cpio --reproducible -o -H newc -R 0:0 > ${outdir}/initrd.cpio)
${hostbindir}/xz -T0 -9 -fz --check=crc32 ${outdir}/initrd.cpio
rm -f ${initrddir}/init

dumpimage -T flat_dt -p 0 -o ${outdir}/kernel.lzma \
${rootpath}/builder/staging_dir/target-aarch64_cortex-a53_musl/image/${initkernelsrc}

echo -e "\ncreate its for initramfs..."
kernelver=$(jq .linux_kernel.version ${outdir}/profiles.json | tr -d '"')
${rootpath}/builder/scripts/mkits.sh -D ${device} -c "config-1" \
-A arm64 -v ${kernelver} -C lzma -a 0x48000000 -e 0x48000000 \
-k ${outdir}/kernel.lzma \
-i ${outdir}/initrd.cpio.xz \
-d ${modeldir}/${initramfsdtb} \
-o ${outdir}/${initramfsnm}.its

echo -e "\ncreate initramfs itb..."
PATH=${kerneldir}/kernel-${kernelver}/scripts/dtc:$PATH \
${hostbindir}/mkimage -f ${outdir}/${initramfsnm}.its \
${outdir}/${initramfsnm}.itb


## create release outputs
echo -e "\ncreate final outputs..."
cd ${rootpath} && mkdir -p release && cd release
mv ${outdir}/*-${model}-squashfs-sysupgrade.itb ./${firmwarenm}.itb
mv ${outdir}/${initramfsnm}.itb .

gzip -9f ${firmwarenm}.itb
gzip -9f ${initramfsnm}.itb

mv ${outdir}/*${model}.manifest ./${variant}-${openwrtver}-${model}.manifest
mv ${outdir}/profiles.json .

## the end
echo -e "\nfiles created:"
ls -lh ${rootpath}/release

echo -e "\nDone."
