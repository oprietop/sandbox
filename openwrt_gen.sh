#//bin/bash
# Build a vanilla OpenWRT image
make info
make clean
make image PROFILE=None PACKAGES="-ppp -ppp-mod-pppoe"
