#!/bin/sh

. map.txt

for i in ${br_ifaces}; do
	ifconfig $i destroy
done

for i in ${vx_ifaces}; do
	ifconfig $i destroy
done
