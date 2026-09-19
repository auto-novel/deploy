.PHONY: install-profile install-service

install-profile:
	cp ./linux/etc/profile.d/* /etc/profile.d/

install-service:
	-systemctl disable --now auto-novel-updater.timer
	-systemctl disable --now deploy@auto-novel.timer
	-systemctl disable --now deploy@auth.timer
	-systemctl disable --now deploy@monitor.timer
	-systemctl disable --now docker-image-prune.timer
	rm -f /etc/systemd/system/auto-novel-updater.service
	rm -f /etc/systemd/system/auto-novel-updater.timer
	rm -f /etc/systemd/system/deploy@.service
	rm -f /etc/systemd/system/deploy@.timer
	rm -f /etc/systemd/system/docker-image-prune.service
	rm -f /etc/systemd/system/docker-image-prune.timer
	cp ./linux/etc/systemd/system/* /etc/systemd/system/
	install -m 0755 ./linux/usr/local/bin/update-apps /usr/local/bin/update-apps
	systemctl daemon-reload
	systemctl enable --now update-apps.timer
	systemctl enable --now auto-novel-tmp-cleanup.timer
