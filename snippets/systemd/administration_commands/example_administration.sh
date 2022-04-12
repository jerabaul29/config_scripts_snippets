##########
# systemctl commands

# start and stop are used to start and stop once, now; will not be active after next reboot
# start the timer, not the service, if want to run the service periodically
sudo systemctl start something.timer
sudo systemctl stop something.timer

# enable and disable are used to enable or disable at boot; will not be active right now
sudo systemctl enable something.service
sudo systemctl diable something.service

# show some status information (ok for service or timer)
sudo systemctl status something.service

# list unit files with information: i) which unit file, ii) state, iii) vendor preset
systemctl list-unit-files
# can be grepped for convenience, for example:

##########
# journalctl commands

# journalctl is a tool to see logs from all systemd managed services; it has many options, like
# looking at only current boot, previous boot, etc
# looking at some time span
# in following: looking in UTC, and starting at the end
journalctl --utc -e

