##########
# creating and modifying unit files

# a service unit defines what to run
# a timer unit defines when to run the service unit
# by convention, the timer unit starts another unit with the same name, i.e. foo.timer starts foo.service

# file units are created and put in /etc/systemd/system

# issue systemctl daemon-reload whenever you edit the unit files
# This makes systemd reload all unit files and re-consider their
# dependencies because systemd caches these files somehow. So
# whenever you change a unit file, this command is required. 
sudo systemctl daemon-reload

##########
# systemctl commands

# if only using a .service per ser, start / stop, enable / disable the service
# if running a .service through a .timer, start / stop, enable / disable the timer, not the service
# i.e. when using a timer to schedule the running of a serice, only enable and start the timer unit, not the service unit
# systemctl enable/disable controls the behaviour when booting
# systemctl start/stop controls the behaviour right now
# enable does not imply start (neither does disable imply stop). This can be overriden with the --now switch.

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

