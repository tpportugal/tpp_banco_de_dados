#!/bin/bash

foreman export systemd /etc/systemd/system
systemctl daemon-reload
systemctl start app.target