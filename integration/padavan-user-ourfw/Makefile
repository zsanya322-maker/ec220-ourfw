# Copy this directory to trunk/user/ourfw in the OURFW Padavan fork.
all:
	@true

clean:
	@true

romfs:
	$(ROMFSINST) -p +x files/ourfw-loader.sh /usr/bin/ourfw-loader.sh
	# ROMFSINST copies plain files with cp and does not create this parent.
	# Missing it used to be silently ignored by Padavan's outer user/Makefile.
	mkdir -p $(ROMFSDIR)/usr/share/ourfw
	$(ROMFSINST) files/defaults.tar.bz2 /usr/share/ourfw/defaults.tar.bz2
	$(ROMFSINST) -d files/www /www/ourfw
