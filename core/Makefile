.PHONY: all install-profile install-service

all: install-profile install-service

install-profile:
	install -Dm0644 ./linux/etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo.sh

install-service:
	install -Dm0644 ./linux/etc/systemd/system/update-apps.service /etc/systemd/system/update-apps.service
	install -Dm0644 ./linux/etc/systemd/system/update-apps.timer /etc/systemd/system/update-apps.timer
	install -Dm0644 ./linux/etc/systemd/system/auto-novel-tmp-cleanup.service /etc/systemd/system/auto-novel-tmp-cleanup.service
	install -Dm0644 ./linux/etc/systemd/system/auto-novel-tmp-cleanup.timer /etc/systemd/system/auto-novel-tmp-cleanup.timer
	install -Dm0755 ./linux/usr/local/bin/update-apps /usr/local/bin/update-apps
	systemctl daemon-reload
	systemctl enable --now update-apps.timer
	systemctl enable --now auto-novel-tmp-cleanup.timer
	systemctl restart update-apps.timer auto-novel-tmp-cleanup.timer
