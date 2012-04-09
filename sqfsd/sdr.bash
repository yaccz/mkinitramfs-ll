#!/bin/bash
# $Id: mkinitramfs-ll/sqfsd/sdr.bash,v 0.5.0.5 2012/04/09 -tclover Exp $
revision=0.5.0.5
usage() {
  cat <<-EOF
  usage: ${0##*/} [--update|--remove] [-r|--sqfsdir=<dir>] -d[|--sqfsd=]<dir>:<dir>
  -r|--sqfsdir <dir>       override default value 'sqfsdir=/sqfsd', if not changed
  -d|--sqfsd <dir>         colon seperated list of directory-ies without the leading '/'
  -a|--arch 32             arch to use for lib\${arch} handling (rc-svcdir and cachedir)
  -f|--fstab               whether to write the necessary mount lines to '/etc/fstab'
  -b|--bsize 131072        use [128k] 131072 bytes block size, which is the default values
  -c|--comp 'xz -Xbjc x86' use xz compressor, optionaly, one can append extra arguments...
  -e|--exclude <dir>       collon separated list of directories to exlude from .sfs image
  -o|--offset <int>        offset used for rebuilding squashed directories, default is 10%
  -U|--update              update the underlying source directory e.g. bin:sbin:lib32:lib64
  -R|--remove              remove the underlying source directory e.g. usr:opt:\${PORTDIR}
  -u|--usage               print this help/usage and exit
  -v|--version             print version string and exit
	
  # squash directries which will speed up system and portage, and the underlying files 
  # system will take much less space especially if there are numerous small files.
  usages: [speed up your system with aufs+squahfs!]
  ${0##*/} -rm -d var/db:var/cache/edb
  # [re-]build system related squashed directories and update the sources directories
  ${0##*/} -up -d bin:sbin:lib32:lib64
EOF
}
[[ $# = 0 ]] && usage && exit 0
opt=$(getopt -o a:b:c:d:e:fo:r:uvUR --long arch:,bsize:,comp:,exclude:,fstab,offset: \
	  --long sqfsdir:,sqfsd:,remove,update,usage,version -n sdr -- "$@" || usage && exit 0)
eval set -- "$opt"
declare -A opts
while [[ $# > 0 ]]; do
	case $1 in
		-u|--usage) usage; exit 0;;
		-v|--version) echo "sdr-${revision}"; exit 0;;
		-e|--exclude) opts[e]="-e ${2//:/ }"; shift 2;;
		-r|--sqfsdir) opts[-r]="${2}"; shift 2;;
		-d|--sqfsd) opts[d]="${2}"; shift 2;;
		-a|--arch) opts[a]="${2}"; shift 2;;
		-f|--fstab) opts[f]=y; shift;;
		-c|--comp) opts[c]="${2}"; shift 2;;
		-o|--offset) opts[o]="${2}"; shift 2;;
		-U|--update) opts[U]=y; shift;;
		-R|--remove) opts[R]=y; shift;;
		--) shift; break;;
	esac
done
info() 	{ echo -ne " \e[1;32m* \e[0m$@\n"; }
error() { echo -ne " \e[1;31m* \e[0m$@\n"; }
die()   { error "$@"; exit 1; }
[[ -n "${opts[r]}" ]] || opts[r]=/sqfsd
[[ -n "${opts[a]}" ]] || opts[a]=64
[[ -n "${opts[b]}" ]] || opts[b]=131072
[[ -n "${opts[c]}" ]] || opts[c]=gzip
[[ -n "${opts[e]}" ]] && opts[e]="-e ${opts[e]}"
sqfsd() 
{
	mkdir -p "${opts[r]}/${dir}"/{ro,rw} || die "failed to create ${dir}/{ro,rw} dirs"
	mksquashfs /${dir} ${opts[r]}/${dir}.tmp.sfs -b ${opts[b]} -comp ${opts[c]} \
		${opts[e]} >/dev/null || die "failed to build ${dir}.sfs img"
	if [[ "${dir}" = lib${opts[a]} ]]; then # move rc-svcdir and cachedir.
		mkdir -p /var/{lib/init.d,cache/splash}
		mount --move "/${dir}/splash/cache" /var/cache/splash &>/dev/null \
			|| die "fled to move cachedir"
		mount --move "/${dir}/rc/init.d" /var/lib/init.d &>/dev/null \
			|| die "failed to move rc-svcdir"
	fi
	if [[ -n "$(mount -t aufs | grep -w ${dir})" ]]; then 
		umount -l /${dir} &>/dev/null || die "failed to umount ${dir} aufs branch"
	fi
	if [[ -n "$(mount -t squashfs | grep ${opts[r]}/${dir}/ro)" ]]; then 
		umount -l ${opts[r]}/${dir}/ro &>/dev/null || die "failed to umount sfs img"
	fi
	rm -rf "${opts[r]}/${dir}"/rw/* || die "failed to clean up ${opts[r]}/${dir}/rw"
	[[ -e ${opts[r]}/${dir}.sfs ]] && rm -f ${opts[r]}/${dir}.sfs 
	mv ${opts[r]}/${dir}.tmp.sfs ${opts[r]}/${dir}.sfs || die "failed to move ${dir}.tmp.sfs img"
	if [[ "${opts[f]}" == "y" ]]; then
		echo "${opts[r]}/${dir}.sfs ${opts[r]}/${dir}/ro squashfs nodev,loop,ro 0 0" \
			>> /etc/fstab || die "fstab write failure 1."
		echo "${dir} /${dir} aufs nodev,udba=reval,br:${opts[r]}/${dir}/rw:${opts[r]}/${dir}/ro 0 0" \
			>> /etc/fstab || die "fstab write failure 2."
	fi
	mount -t squashfs ${opts[r]}/${dir}.sfs ${opts[r]}/${dir}/ro \
		-o nodev,loop,ro &>/dev/null || die "failed to mount ${dir}.sfs img"
	if [[ -n "${opts[R]}" ]]; then # now you can up[date] or rm the source dir
		rm -rf /${dir}/* || die "failed to clean up ${opts[r]}/${dir}"
	elif [[ -n "${opts[U]}" ]]; then echo >/tmp/sdr
		cp -aru ${opts[r]}/${dir}/ro/* /${dir}/ 2>>/tmp/sdr || {
			for file in $(sed -e "s|.*\`||g" -e "s|':.*||g" /tmp/sdr)
			do cp -a ${opts[r]}/${dir}/ro/${file#/${dir}/} /tmp/ && \
			mv /tmp/${file##*/} ${file} || info "failed to move ${file}"; done
		}
	fi
	mount -t aufs ${dir} /${dir} \
		-o nodev,udba=reval,br:${opts[r]}/${dir}/rw:${opts[r]}/${dir}/ro \
		&>/dev/null || die "failed to mount ${dir} aufs branch."
	if [[ "${dir}" = lib${opts[a]} ]]; then # move back rc-svcdir and cachedir
		mount --move /var/cache/splash "/${dir}/splash/cache" &>/dev/nul \
			|| die "failed to move back cachedir"
		mount --move /var/lib/init.d "/${dir}/rc/init.d" &>/dev/null \
			|| die "failed to move back rc-svcdir"
	fi
	echo -ne "\e[1;32m>>> ...sucessfully build squashed ${dir}\e[0m\n"
}
for dir in ${opts[d]//:/ }; do
	if [[ -e /sqfsd/${dir}.sfs ]]; then
		if [[ ${opts[o]:-10} != 0 ]]; then
			ro_size=$(du -sk ${opts[r]}/${dir}/ro | awk '{print $1}')
			rw_size=$(du -sk ${opts[r]}/${dir}/rw | awk '{print $1}')
			if (( ( ${rw_size}*100/${ro_size} ) < ${opts[o]:-10} )); then
				info "${dir}: skiping... there's an '-o' offset option to change the offset"
			else echo -ne "\e[1;32m>>> updating squashed ${dir}...\e[0m\n"; sqfsd; fi
		else echo -ne "\e[1;32m>>> updating squashed ${dir}...\e[0m\n"; sqfsd; fi
	else echo -ne "\e[1;32m>>> building squashed ${dir}...\e[0m\n"; sqfsd; fi			
done
unset opt opts ro_size rw_size
# vim:fenc=utf-8:ci:pi:sts=0:sw=4:ts=4: