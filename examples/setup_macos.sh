#!/bin/bash
# macOS network tuning for high-concurrency servers
sudo sysctl -w kern.ipc.somaxconn=16384
sudo sysctl -w net.inet.ip.portrange.first=10000
sudo sysctl -w net.inet.ip.portrange.last=65535
sudo sysctl -w net.inet.tcp.msl=1000
sudo sysctl -w kern.maxfiles=655350
sudo sysctl -w kern.maxfilesperproc=655350
echo "⚡ macOS tuning applied. Remember to also run: ulimit -n 65535"
