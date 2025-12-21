.PHONY: install-service

install-service:
	cp ./script/systemd/* /etc/systemd/system/
	systemctl daemon-reload
	systemctl enable auto-novel-updater.timer
	systemctl start auto-novel-updater.timer
	systemctl enable auto-novel-tmp-cleanup.timer
	systemctl start auto-novel-tmp-cleanup.timer
