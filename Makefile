.PHONY: install-profile install-service

install-profile:
	cp ./linux/etc/profile.d/* /etc/profile.d/

install-service:
	cp ./linux/etc/systemd/system/* /etc/systemd/system/
	systemctl daemon-reload
	systemctl enable auto-novel-updater.timer
	systemctl start auto-novel-updater.timer
	systemctl enable auto-novel-tmp-cleanup.timer
	systemctl start auto-novel-tmp-cleanup.timer
