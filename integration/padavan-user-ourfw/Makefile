# Copy this directory to trunk/user/ourfw in the OURFW Padavan fork.
all:
	@true

clean:
	@true

romfs:
	$(ROMFSINST) -p +x files/ourfw-loader.sh /usr/bin/ourfw-loader.sh
	$(ROMFSINST) files/defaults.tar.bz2 /usr/share/ourfw/defaults.tar.bz2
	$(ROMFSINST) -d files/www /www/ourfw
