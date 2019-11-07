
install-exec-local:
	if [ "$(distribution)" = "ArchLinux" ] ; then			\
	  $(mkinstalldirs) "$(DESTDIR)/usr/lib/systemd/system";				\
	  $(INSTALL_SCRIPT) $(srcdir)/pdnsd.service "$(DESTDIR)/usr/lib/systemd/system/pdnsd.service";\
	fi

