.PHONY: install-profile install-service

install-profile:
	cp ./linux/etc/profile.d/* /etc/profile.d/

install-service:
	cp ./linux/etc/systemd/system/* /etc/systemd/system/
	install -m 0755 ./linux/usr/local/bin/update-apps /usr/local/bin/update-apps
	systemctl daemon-reload
	systemctl enable --now update-apps.timer
	systemctl enable --now auto-novel-tmp-cleanup.timer
