#!/bin/sh
set -e  # Enable error trapping


###################################
###          FUNCTIONS          ###
###################################


#----------------------------#
get_sources() {              #
#----------------------------#
  local IFS

  # Test if the packages must be downloaded
  if [ ! "$HPKG" = "1" ] ; then
    return
  fi

  # Modify the 'internal field separator' to break on 'LF' only
  IFS=$'\x0A'

  if [ ! -d $BUILDDIR/sources ] ; then mkdir $BUILDDIR/sources ; fi
  cd $BUILDDIR/sources

  > MISSING_FILES.DMP  # Files not in md5sum end up here

  if [ -f MD5SUMS ] ; then rm MD5SUMS ; fi
  if [ -f MD5SUMS-$VERSION ] ; then rm MD5SUMS-$VERSION ; fi

  # Retrieve the master md5sum file
  download "" MD5SUMS

  # Iterate through each package and grab it, along with any patches it needs.
  for i in `cat $JHALFSDIR/packages` ; do
    PKG=`echo $i | sed -e 's/-version.*//' \
                       -e 's/-file.*//' \
                       -e 's/uclibc/uClibc/' `

    # Needed for Groff patchlevel patch on UTF-8 branch
    GROFFLEVEL=`grep "groff-patchlevel" $JHALFSDIR/packages | sed -e 's/groff-patchlevel //' -e 's/"//g'`

    #
    # How to deal with orphan packages..??
    #
    VRS=`echo $i | sed -e 's/.* //' -e 's/"//g'`
    case "$PKG" in
      "expect-lib" )        continue ;; # not valid packages
      "linux-dl" )          continue ;;
      "groff-patchlevel" )  continue ;;
      "uClibc-patch" )      continue ;;

      "tcl" )           FILE="$PKG$VRS-src.tar.bz2"             ; download $PKG $FILE ;;
      "vim-lang" )      FILE="vim-$VRS-lang.tar.bz2"; PKG="vim" ; download $PKG $FILE ;;
      "udev-config" )   FILE="$VRS" ; PKG="udev"                ; download $PKG $FILE ;;

      "uClibc-locale" ) FILE="$PKG-$VRS.tar.bz2" ; PKG="uClibc"
                download $PKG $FILE
                # There can be no patches for this file
                continue ;;

      "gcc" )   download $PKG "gcc-core-$VRS.tar.bz2"
                download $PKG "gcc-g++-$VRS.tar.bz2"
        ;;
      "glibc")  download $PKG "$PKG-$VRS.tar.bz2"
                download $PKG "$PKG-libidn-$VRS.tar.bz2"
        ;;
      * )     FILE="$PKG-$VRS.tar.bz2"
              download $PKG $FILE
        ;;
    esac

    for patch in `grep "$PKG-&$PKG" $JHALFSDIR/patches` ; do
      PATCH=`echo $patch | sed 's@&'$PKG'-version;@'$VRS'@'`
      download $PKG $PATCH
    done

  done

  # .... U G L Y .... what to do with the grsecurity patch to the kernel..
  download grsecurity `grep grsecurity $JHALFSDIR/patches`

  # .... U G L Y .... deal with uClibc-locale-xxxxx.tar.bz2 format issue.
  bzcat uClibc-locale-030818.tar.bz2 | gzip > uClibc-locale-030818.tgz

  if [[ -s $BUILDDIR/sources/MISSING_FILES.DMP ]]; then
    echo  -e "\n\n${tab_}${RED} One or more files were not retrieved.\n${tab_} Check <MISSING_FILES.DMP> for names ${OFF}\n\n"
  fi
}


#----------------------------#
chapter4_Makefiles() {       # Initialization of the system
#----------------------------#
  local TARGET LOADER

  echo  "${YELLOW}  Processing Chapter-4 scripts ${OFF}"

  # Define a few model dependant variables
  if [[ ${MODEL} = "uclibc" ]]; then
    TARGET="tools-linux-uclibc"; LOADER="ld-uClibc.so.0"
  else
    TARGET="tools-linux-gnu";    LOADER="ld-linux.so.2"
    fi

  # 022-
  # If /home/hlfs is already present in the host, we asume that the
  # hlfs user and group are also presents in the host, and a backup
  # of their bash init files is made.
(
cat << EOF
020-creatingtoolsdir:
	@\$(call echo_message, Building)
	@mkdir -v \$(MOUNT_PT)/tools && \\
	rm -fv /tools && \\
	ln -sv \$(MOUNT_PT)/tools /
	@if [ ! -d \$(MOUNT_PT)/sources ]; then \\
		mkdir \$(MOUNT_PT)/sources; \\
	fi;
	@chmod a+wt \$(MOUNT_PT)/sources && \\
	touch \$@

021-addinguser:  020-creatingtoolsdir
	@\$(call echo_message, Building)
	@if [ ! -d /home/lfs ]; then \\
		groupadd lfs; \\
		useradd -s /bin/bash -g lfs -m -k /dev/null lfs; \\
	else \\
		touch user-lfs-exist; \\
	fi;
	@chown lfs \$(MOUNT_PT)/tools && \\
	chown lfs \$(MOUNT_PT)/sources && \\
	touch \$@

022-settingenvironment:  021-addinguser
	@\$(call echo_message, Building)
	@if [ -f /home/lfs/.bashrc -a ! -f /home/lfs/.bashrc.XXX ]; then \\
		mv -v /home/lfs/.bashrc /home/lfs/.bashrc.XXX; \\
	fi;
	@if [ -f /home/lfs/.bash_profile  -a ! -f /home/lfs/.bash_profile.XXX ]; then \\
		mv -v /home/lfs/.bash_profile /home/lfs/.bash_profile.XXX; \\
	fi;
	@echo "set +h" > /home/lfs/.bashrc && \\
	echo "umask 022" >> /home/lfs/.bashrc && \\
	echo "HLFS=\$(MOUNT_PT)" >> /home/lfs/.bashrc && \\
	echo "LC_ALL=POSIX" >> /home/lfs/.bashrc && \\
	echo "PATH=/tools/bin:/bin:/usr/bin" >> /home/lfs/.bashrc && \\
	echo "export HLFS LC_ALL PATH" >> /home/lfs/.bashrc && \\
	echo "" >> /home/lfs/.bashrc && \\
	echo "target=$(uname -m)-${TARGET}" >> /home/lfs/.bashrc && \\
	echo "ldso=/tools/lib/${LOADER}" >> /home/lfs/.bashrc && \\
	echo "export target ldso" >> /home/lfs/.bashrc && \\
	echo "source $JHALFSDIR/envars" >> /home/lfs/.bashrc && \\
	chown lfs:lfs /home/lfs/.bashrc && \\
	touch envars && \\
	touch \$@
EOF
) >> $MKFILE.tmp

}

#----------------------------#
chapter5_Makefiles() {       # Bootstrap or temptools phase
#----------------------------#
  local file
  local this_script
  
  echo "${YELLOW}  Processing Chapter-5 scripts${OFF}"

  for file in chapter05/* ; do
    # Keep the script file name
    this_script=`basename $file`

    # Skip this script depending on jhalfs.conf flags set.
    case $this_script in
      # If no testsuites will be run, then TCL, Expect and DejaGNU aren't needed
      *tcl* )     [[ "$TOOLCHAINTEST" = "0" ]] && continue; ;;
      *expect* )  [[ "$TOOLCHAINTEST" = "0" ]] && continue; ;;
      *dejagnu* ) [[ "$TOOLCHAINTEST" = "0" ]] && continue; ;;
        # Test if the stripping phase must be skipped
      *stripping* ) [[ "$STRIP" = "0" ]] && continue ;;
        # Select the appropriate library
      *glibc*)    [[ ${MODEL} = "uclibc" ]] && continue ;;
      *uclibc*)   [[ ${MODEL} = "glibc" ]]  && continue ;;
      *) ;;
    esac

    # First append each name of the script files to a list (this will become
    # the names of the targets in the Makefile
    chapter5="$chapter5 $this_script"

    # Grab the name of the target (minus the -headers or -cross in the case of gcc
    # and binutils in chapter 5)
    name=`echo $this_script | sed -e 's@[0-9]\{3\}-@@' -e 's@-cross@@' -e 's@-headers@@'`

    # >>>>>>>>>> U G L Y <<<<<<<<<
    # Adjust 'name' and patch a few scripts on the fly..
    case $name in
      linux-libc) name=linux-libc-headers
      ;;
      uclibc) # this sucks as method to deal with gettext/libint inside uClibc
        sed 's@^cd gettext-runtime@cd ../gettext-*/gettext-runtime@' -i chapter05/$this_script
      ;;
     gcc) # to compensate for the compiler test inside gcc (which fails), disable error trap
        sed 's@^gcc -o test test.c@set +e; gcc -o test test.c@' -i chapter05/$this_script
      ;;
    esac

    # Set the dependency for the first target.
    if [ -z $PREV ] ; then PREV=022-settingenvironment ; fi


    #--------------------------------------------------------------------#
    #         >>>>>>>> START BUILDING A Makefile ENTRY <<<<<<<<          #
    #--------------------------------------------------------------------#
    #
    # Drop in the name of the target on a new line, and the previous target
    # as a dependency. Also call the echo_message function.
    wrt_target "$this_script" "$PREV"

    # Find the version of the command files, if it corresponds with the building of
    # a specific package
    vrs=`grep "^$name-version" $JHALFSDIR/packages | sed -e 's/.* //' -e 's/"//g'`
    # If $vrs isn't empty, we've got a package...
    if [ "$vrs" != "" ] ; then
      # Deal with non-standard names
      case $name in
        tcl)    FILE="$name$vrs-src.tar"  ;;
        uclibc) FILE="uClibc-$vrs.tar"    ;;
        gcc)    FILE="gcc-core-$vrs.tar"  ;;
        *)      FILE="$name-$vrs.tar"     ;;
      esac
     # Insert instructions for unpacking the package and to set the PKGDIR variable.
     wrt_unpack "$FILE"
  fi

    case $this_script in
      *binutils* )  # Dump the path to sources directory for later removal
        echo -e '\techo "$(MOUNT_PT)$(SRC)/$$ROOT" >> sources-dir' >> $MKFILE.tmp
        ;;
      *adjusting* )  # For the Adjusting phase we must to cd to the binutils-build directory.
        echo -e '\t@echo "export PKGDIR=$(MOUNT_PT)$(SRC)/binutils-build" > envars' >> $MKFILE.tmp
        ;;
      * )  # Everything else, add a true statment so we don't confuse make
        echo -e '\ttrue' >> $MKFILE.tmp
        ;;
    esac

    # Insert date and disk usage at the top of the log file, the script run
    # and date and disk usage again at the bottom of the log file.
    wrt_run_as_su "${this_script}" "${file}"

    # Remove the build directory(ies) except if the package build fails
    # (so we can review config.cache, config.log, etc.)
    # For Binutils the sources must be retained for some time.
    if [ "$vrs" != "" ] ; then
      if [[ ! `_IS_ $this_script binutils` ]]; then
      wrt_remove_build_dirs "$name"
      fi
    fi

    # Remove the Binutils pass 1 sources after a successful Adjusting phase.
    if [[ `_IS_ $this_script adjusting` ]] ; then
(
cat << EOF
	@rm -r \`cat sources-dir\` && \\
	rm -r \$(MOUNT_PT)\$(SRC)/binutils-build && \\
	rm sources-dir
EOF
) >> $MKFILE.tmp
    fi

    # Include a touch of the target name so make can check if it's already been made.
    echo -e '\t@touch $@' >> $MKFILE.tmp
    #
    #--------------------------------------------------------------------#
    #              >>>>>>>> END OF Makefile ENTRY <<<<<<<<               #
    #--------------------------------------------------------------------#

    # Keep the script file name for Makefile dependencies.
    PREV=$this_script
  done  # end for file in chapter05/*
}


#----------------------------#
chapter6_Makefiles() {       # sysroot or chroot build phase
#----------------------------#
  local TARGET LOADER
  local file
  local this_script

  #
  # Set these definitions early and only once
  #
  if [[ ${MODEL} = "uclibc" ]]; then
    TARGET="pc-linux-uclibc"; LOADER="ld-uClibc.so.0"
  else
    TARGET="pc-linux-gnu";    LOADER="ld-linux.so.2"
  fi

  echo -e "${YELLOW}  Processing Chapter-6 scripts ${OFF}"
  for file in chapter06/* ; do
    # Keep the script file name
    this_script=`basename $file`

    # Skip this script depending on jhalfs.conf flags set.
    case $this_script in
        # We'll run the chroot commands differently than the others, so skip them in the
        # dependencies and target creation.
      *chroot* )  continue ;;
        # Test if the stripping phase must be skipped
      *-stripping* )  [[ "$STRIP" = "0" ]] && continue ;;
        # Select the appropriate library
      *glibc*)    [[ ${MODEL} = "uclibc" ]] && continue ;;
      *uclibc*)   [[ ${MODEL} = "glibc" ]]  && continue ;;
      *) ;;
    esac

    # First append each name of the script files to a list (this will become
    # the names of the targets in the Makefile
    chapter6="$chapter6 $this_script"

    # Grab the name of the target
    name=`echo $this_script | sed -e 's@[0-9]\{3\}-@@'`

    #
    # Sed replacement for 'nodump' tag in xml scripts until Manuel has a chance to fix them
    #
    case $name in
      kernfs) 
            # We are using LFS instead of HLFS..
          sed 's/HLFS/LFS/' -i chapter06/$this_script
            # Remove sysctl code if host does not have grsecurity enabled
          if [[ "$GRSECURITY_HOST" = "0" ]]; then
            sed '/sysctl/d' -i chapter06/$this_script
          fi 
        ;;
      module-init-tools)
          if [[ "$TEST" = "0" ]]; then  # This needs rework....
            sed '/make distclean/d' -i chapter06/$this_script
          fi
        ;;
      glibc)  # PATCH.. Turn off error trapping for the remainder of the script.
          sed 's|^make install|make install; set +e|'  -i chapter06/$this_script
        ;;
      uclibc) # PATCH..
          sed 's/EST5EDT/${TIMEZONE}/' -i chapter06/$this_script
            # PATCH.. Cannot use interactive programs/scripts.
          sed 's/make menuconfig/make oldconfig/' -i chapter06/$this_script
          sed 's@^cd gettext-runtime@cd ../gettext-*/gettext-runtime@' -i chapter06/$this_script
        ;;
      gcc)  # PATCH..
          sed 's/rm /rm -f /' -i chapter06/$this_script
        ;;
    esac

    #--------------------------------------------------------------------#
    #         >>>>>>>> START BUILDING A Makefile ENTRY <<<<<<<<          #
    #--------------------------------------------------------------------#
    #
    # Drop in the name of the target on a new line, and the previous target
    # as a dependency. Also call the echo_message function.
    wrt_target "$this_script" "$PREV"

    # Find the version of the command files, if it corresponds with the building of
    # a specific package
    vrs=`grep "^$name-version" $JHALFSDIR/packages | sed -e 's/.* //' -e 's/"//g'`

    # If $vrs isn't empty, we've got a package...
    # Insert instructions for unpacking the package and changing directories
    if [ "$vrs" != "" ] ; then
      # Deal with non-standard names
      case $name in
        tcl)    FILE="$name$vrs-src.tar.*" ;;
        uclibc) FILE="uClibc-$vrs.tar.*" ;;
        gcc)    FILE="gcc-core-$vrs.tar.*" ;;
        *)      FILE="$name-$vrs.tar.*" ;;
      esac
      wrt_unpack2 "$FILE"
      wrt_target_vars
    fi

    case $this_script in
      *readjusting*) # For the Re-Adjusting phase we must to cd to the binutils-build directory.
        echo -e '\t@echo "export PKGDIR=$(SRC)/binutils-build" > envars' >> $MKFILE.tmp
        ;;
      *glibc* | *uclibc* ) # For glibc and uClibc we need to set TIMEZONE envar.
        wrt_export_timezone
        ;;
      *groff* ) # For Groff we need to set PAGE envar.
        wrt_export_pagesize
        ;;
    esac

    # In the mount of kernel filesystems we need to set HLFS and not to use chroot.
    if [[ `_IS_ $this_script kernfs` ]] ; then
      wrt_run_as_root "${this_script}" "${file}"
    #
    # The rest of Chapter06
    else
      wrt_run_as_chroot1 "${this_script}" "${file}"
    fi
    #
    # Remove the build directory(ies) except if the package build fails.
    if [ "$vrs" != "" ] ; then
      wrt_remove_build_dirs "$name"
    fi
    #
    # Remove the Binutils pass 2 sources after a successful Re-Adjusting phase.
    if [[ `_IS_ $this_script readjusting` ]] ; then
(
cat << EOF
	@rm -r \`cat sources-dir\` && \\
	rm -r \$(MOUNT_PT)\$(SRC)/binutils-build && \\
	rm sources-dir
EOF
) >> $MKFILE.tmp
    fi

    # Include a touch of the target name so make can check if it's already been made.
    echo -e '\t@touch $@' >> $MKFILE.tmp
    #
    #--------------------------------------------------------------------#
    #              >>>>>>>> END OF Makefile ENTRY <<<<<<<<               #
    #--------------------------------------------------------------------#

    # Keep the script file name for Makefile dependencies.
    PREV=$this_script
  done # end for file in chapter06/*

}

#----------------------------#
chapter7_Makefiles() {       # Create a bootable system.. kernel, bootscripts..etc
#----------------------------#
  local file
  local this_script
  
  echo  "${YELLOW}  Processing Chapter-7 scripts ${OFF}"
  for file in chapter07/*; do
    # Keep the script file name
    this_script=`basename $file`

    # Grub must be configured manually.
    # The filesystems can't be unmounted via Makefile and the user
    # should enter the chroot environment to create the root
    # password, edit several files and setup Grub.
    case $this_script in
      *grub)    continue  ;;
      *reboot)  continue  ;;
      *console) continue  ;; # Use the file generated by lfs-bootscripts

      *kernel)  # How does Manuel add this string to the file..
        sed 's|cd \$PKGDIR.*||'         -i chapter07/$this_script
          # You cannot run menuconfig from within the makefile
        sed 's|make menuconfig|make oldconfig|' -i chapter07/$this_script
          # The files in the conglomeration dir are xxx.bz2
        sed 's|.patch.gz|.patch.bz2|'   -i chapter07/$this_script
        sed 's|gunzip|bunzip2|'         -i chapter07/$this_script
          # If defined include the keymap in the kernel
        if [[ -n "$KEYMAP" ]]; then
          sed "s|^loadkeys -m.*>|loadkeys -m $KEYMAP >|" -i chapter07/$this_script
        else
          sed '/loadkeys -m/d'          -i chapter07/$this_script
          sed '/drivers\/char/d'        -i chapter07/$this_script
        fi
          # If no .config file is supplied, the kernel build is skipped
        [[ -z $CONFIG ]] && continue
         ;;
      *usage)   # The script bombs, disable error trapping
        sed 's|set -e|set +e|'  -i chapter07/$this_script
         ;;
      *profile) # Add the config values to the script
        sed "s|LC_ALL=\*\*EDITME.*EDITME\*\*|LC_ALL=$LC_ALL|" -i chapter07/$this_script
        sed "s|LANG=\*\*EDITME.*EDITME\*\*|LANG=$LANG|"       -i chapter07/$this_script
         ;;
    esac

    # First append then name of the script file to a list (this will become
    # the names of the targets in the Makefile
    chapter7="$chapter7 $this_script"

    #--------------------------------------------------------------------#
    #         >>>>>>>> START BUILDING A Makefile ENTRY <<<<<<<<          #
    #--------------------------------------------------------------------#
    #
    # Drop in the name of the target on a new line, and the previous target
    # as a dependency. Also call the echo_message function.
    wrt_target "$this_script" "$PREV"

    if [[ `_IS_ $this_script bootscripts` ]] ; then
      vrs=`grep "^lfs-bootscripts-version" $JHALFSDIR/packages | sed -e 's/.* //' -e 's/"//g'`
      FILE="lfs-bootscripts-$vrs.tar.*"
      # The bootscript pkg references both lfs AND blfs bootscripts...
      #  see XML script for other additions to bootscripts file
      # PATCH
      vrs=`grep "^blfs-bootscripts-version" $JHALFSDIR/packages | sed -e 's/.* //' -e 's/"//g'`
      sed "s|make install$|make install; cd ../blfs-bootscripts-$vrs|" -i chapter07/$this_script
      wrt_unpack2 "$FILE"
(
cat  << EOF
	echo "\$(MOUNT_PT)\$(SRC)/blfs-bootscripts-$vrs" > sources-dir
EOF
) >> $MKFILE.tmp
    fi

    if [[ `_IS_ $this_script kernel` ]] ; then
      # not much really, script does everything..
      echo -e "\t@cp -f $CONFIG \$(MOUNT_PT)/sources/kernel-config" >> $MKFILE.tmp
    fi

    # Check if we have a real /etc/fstab file
    if [[ `_IS_ $this_script fstab` ]] && [[ -n "$FSTAB" ]] ; then
      wrt_copy_fstab "$this_script"
    else
      # Initialize the log and run the script
      wrt_run_as_chroot2 "${this_script}" "${file}"
    fi

    # Remove the build directory except if the package build fails.
    if [[ `_IS_ $this_script bootscripts` ]]; then
(
cat << EOF
	@ROOT=\`head -n1 /tmp/unpacked | sed 's@^./@@;s@/.*@@'\` && \\
	rm -r \$(MOUNT_PT)\$(SRC)/\$\$ROOT
	@rm -r \`cat sources-dir\` && \\
	rm sources-dir
EOF
) >> $MKFILE.tmp
    fi

    # Include a touch of the target name so make can check if it's already been made.
    echo -e '\t@touch $@' >> $MKFILE.tmp
    #
    #--------------------------------------------------------------------#
    #              >>>>>>>> END OF Makefile ENTRY <<<<<<<<               #
    #--------------------------------------------------------------------#

    # Keep the script file name for Makefile dependencies.
    PREV=$this_script
  done  # for file in chapter07/*
}


#----------------------------#
build_Makefile() {           # Construct a Makefile from the book scripts
#----------------------------#
  echo -e "${GREEN}Creating Makefile... ${OFF}"

  cd $JHALFSDIR/${PROGNAME}-commands
  # Start with a clean Makefile.tmp file
  >$MKFILE.tmp

  chapter4_Makefiles
  chapter5_Makefiles
  chapter6_Makefiles
  chapter7_Makefiles

  # Add a header, some variables and include the function file
  # to the top of the real Makefile.
(
    cat << EOF
$HEADER

SRC= /sources
MOUNT_PT= $BUILDDIR
PAGE= $PAGE
TIMEZONE= $TIMEZONE

include makefile-functions

EOF
) > $MKFILE


  # Add chroot commands
  i=1
  for file in chapter06/*chroot* ; do
    chroot=`cat $file | sed -e '/#!\/bin\/sh/d' \
          -e '/^export/d' \
          -e '/^logout/d' \
          -e 's@ \\\@ @g' | tr -d '\n' |  sed -e 's/  */ /g' \
                                              -e 's|\\$|&&|g' \
                                              -e 's|exit||g' \
                                              -e 's|$| -c|' \
                                              -e 's|"$$HLFS"|$(MOUNT_PT)|'\
                                              -e 's|set -e||'`
    echo -e "CHROOT$i= $chroot\n" >> $MKFILE
    i=`expr $i + 1`
  done

  # Drop in the main target 'all:' and the chapter targets with each sub-target
  # as a dependency.
(
  cat << EOF
all:  chapter4 chapter5 chapter6 chapter7
	@\$(call echo_finished,$VERSION)

chapter4:  020-creatingtoolsdir 021-addinguser 022-settingenvironment

chapter5:  chapter4 $chapter5 restore-hlfs-env

chapter6:  chapter5 $chapter6

chapter7:  chapter6 $chapter7

clean-all:  clean
	rm -rf ./{hlfs-commands,logs,Makefile,dump-hlfs-scripts.xsl,functions,packages,patches}

clean:  clean-chapter7 clean-chapter6 clean-chapter5 clean-chapter4

clean-chapter4:
	-if [ ! -f user-hlfs-exist ]; then \\
		userdel hlfs; \\
		rm -rf /home/hlfs; \\
	fi;
	rm -rf \$(MOUNT_PT)/tools
	rm -f /tools
	rm -f envars user-hlfs-exist
	rm -f 02* logs/02*.log

clean-chapter5:
	rm -rf \$(MOUNT_PT)/tools/*
	rm -f $chapter5 restore-hlfs-env sources-dir
	cd logs && rm -f $chapter5 && cd ..

clean-chapter6:
	-umount \$(MOUNT_PT)/sys
	-umount \$(MOUNT_PT)/proc
	-umount \$(MOUNT_PT)/dev/shm
	-umount \$(MOUNT_PT)/dev/pts
	-umount \$(MOUNT_PT)/dev
	rm -rf \$(MOUNT_PT)/{bin,boot,dev,etc,home,lib,media,mnt,opt,proc,root,sbin,srv,sys,tmp,usr,var}
	rm -f $chapter6
	cd logs && rm -f $chapter6 && cd ..

clean-chapter7:
	rm -f $chapter7
	cd logs && rm -f $chapter7 && cd ..

restore-hlfs-env:
	@\$(call echo_message, Building)
	@if [ -f /home/lfs/.bashrc.XXX ]; then \\
		mv -fv /home/lfs/.bashrc.XXX /home/hlfs/.bashrc; \\
	fi;
	@if [ -f /home/hlfs/.bash_profile.XXX ]; then \\
		mv -v /home/lfs/.bash_profile.XXX /home/hlfs/.bash_profile; \\
	fi;
	@chown lfs:lfs /home/lfs/.bash* && \\
	touch \$@

EOF
) >> $MKFILE

  # Bring over the items from the Makefile.tmp
  cat $MKFILE.tmp >> $MKFILE
  rm $MKFILE.tmp
  echo -ne "${GREEN}done\n${OFF}"
}

