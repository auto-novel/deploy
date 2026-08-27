.PHONY: install-profile install-service

install-profile:
	cp ./linux/etc/profile.d/* /etc/profile.d/

install-service:
	-systemctl disable --now auto-novel-updater.timer
	rm -f /etc/systemd/system/auto-novel-updater.service
	rm -f /etc/systemd/system/auto-novel-updater.timer
	cp ./linux/etc/systemd/system/* /etc/systemd/system/
	systemctl daemon-reload
	systemctl enable --now deploy@auto-novel.timer
	systemctl enable --now deploy@auth.timer
	systemctl enable --now deploy@monitor.timer
	systemctl enable --now docker-image-prune.timer
	systemctl enable --now auto-novel-tmp-cleanup.timer
