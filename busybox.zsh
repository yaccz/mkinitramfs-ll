#!/bin/zsh
# $Id: mkinitramfs-ll/busybox.zsh,v 0.11.1 2012/10/16 21:54:49 -tclover Exp $
usage() {
  cat <<-EOF
 usage: ${(%):-%1x} [-m|-minimal] [-ucl i386]

  -d|-usrdir [usr]        copy busybox binary file to usr/bin
  -n|-minimal             build busybox with minimal applets, default is full applets
     -ucl i386            arch string needed to build busybox against uClibc	
  -v|-version 1.20.0      use 1.20.0 instead of latest version of busybox
  -u|-usage               print the usage/help and exit
EOF
exit $?
}
error() { print -P " %B%F{red}*%b%f $@"; }
die()   { error $@; exit 1; }
alias die='die "%F{yellow}%1x:%U${(%):-%I}%u:%f" $@'
zmodload zsh/zutil
zparseopts -E -D -K -A opts n minimal d:: usrdir:: ucl: u usage v: version: || usage
if [[ -n ${(k)opts[-u]} ]] || [[ -n ${(k)opts[-usage]} ]] { usage }
if [[ $# < 1 ]] { typeset -A opts }
if [[ -f mkinitramfs-ll.conf ]] { source mkinitramfs-ll.conf 
} else { die "no mkinitramfs-ll.conf found" }
:	${opts[-workdir]:=${opts[-W]:-$(pwd)}}
:	${opts[-usrdir]:=${opts[-d]:-$opts[-workdir]/usr}}
mkdir -p ${opts[-usrdir]}/bin
pushd ${PORTDIR:-/usr/portage}/sys-apps/busybox || die
if [[ -n ${(k)opts[-v]} ]] || [[ -n ${(k)opts[-version]} ]] { 
:	opts[-pkg]="=busybox-${opts[-version]:-${opts[-v]}}"
} else { opts[-pkg]=busybox }
opts[-pkg]=$(emerge -pvO ${opts[-pkg]} | grep -o "busybox-[-0-9.r]*")
ebuild ${opts[-pkg]}.ebuild clean || die "clean failed"
ebuild ${opts[-pkg]}.ebuild unpack || die "unpack failed"
pushd ${PORTAGE_TMPDIR:-/var/tmp}/portage/sys-apps/${opts[-pkg]}/work/${opts[-pkg]} || die
if [[ -n ${(k)opts[-n]} ]] || [[ -n ${(k)opts[-minimal]} ]] { make allnoconfig || die
	for cfg ($(< ${opts[-workdir]}/busybox.cfg))
	sed -e "s|# ${cfg%'=y'} is not set|${cfg}|" -i .config || die 
} else {
	make defconfig || die "defconfig failed" 
	sed -e "s|# CONFIG_STATIC is not set|CONFIG_STATIC=y|" \
		-e "s|# CONFIG_INSTALL_NO_USR is not set|CONFIG_INSTALL_NO_USR=y|" \
		-i .config || die
}
if [[ -n ${opts[-ucl]} ]] {
sed -e "s|CONFIG_CROSS_COMPILER_PREFIX=\"\"|CONFIG_CROSS_COMPILER_PREFIX=\"${opts[-ucl]}\"|" \
	-i .config || die "setting uClib ARCH failed"
}
make || die "failed to build busybox"
cp -a busybox ${opts[-usrdir]}/bin || die
popd || die
ebuild ${opts[-pkg]}.ebuild clean || die
popd || die
unset opts[-pkg] opts[-n] opts[-minimal] opts[-ucl]
# vim:fenc=utf-8ft=zsh:ci:pi:sts=0:sw=4:ts=4:
