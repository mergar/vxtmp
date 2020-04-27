#!/bin/sh
: ${distdir="/usr/local/cbsd"}
unset workdir

# MAIN
[ -z "${cbsd_workdir}" ] && . /etc/rc.conf
[ -z "${cbsd_workdir}" ] && exit

workdir="${cbsd_workdir}"

[ ! -f "${distdir}/cbsd.conf" ] && exit

. ${distdir}/cbsd.conf
. ${distdir}/nc.subr
. ${distdir}/tools.subr
. ${strings}

get_vxlan_ip()
{
	local _id="${1}"
	local _ip

	eval _ip="\$HOST${_id}_VXLAN_IP"
	[ -z "${_ip}" ] && err 1 "Unable to determine remote VXLAN for node id $i"
	printf "${_ip}"
}

#MTU="1500"
#Encapsulation adds 50 bytes to each packet(This is also true of most 1-to-1 tunnels)
MTU="1450"
MY_VXLAN_IP=
MY_ID=

HOST_LIST="2a01:4f8:241:500c::1 2a01:4f8:241:500b::1 2a05:3580:d800:20f7::1"
MESH_NET="10.10.10.0/24"
NEIGHBOR=

nodes=0
for i in ${HOST_LIST}; do
	nodes=$(( nodes + 1 ))
	ping6 -i 0.1 -c1 -S ${i} ${i} > /dev/null 2>&1
	_ret=$?
	if [ ${_ret} -eq 0 ]; then
		MY_VXLAN_IP="${i}"
		MY_ID="${nodes}"
		export HOST${nodes}_VXLAN_IP="${i}"
		continue
	fi
	export HOST${nodes}_VXLAN_IP="${i}"
	NEIGHBOR_VXLAN_IPS="${NEIGHBOR_VXLAN_IPS} ${i}"
	NEIGHBOR_NODES_ID="${NEIGHBOR_NODES_ID} ${nodes}"
done

if [ -z "${MY_VXLAN_IP}" ]; then
	echo "Unable to determine my ip from list: ${HOST_LIST}"
	exit 0
fi

sqllistdelimer="."
sqllist "${MESH_NET}" _s1 _s2 _s3 _s4

cat > map.txt <<EOF
MY ID: ${MY_ID}
MY VXLAN IP: ${MY_VXLAN_IP}
EOF

tunnels=0
for i in ${NEIGHBOR_NODES_ID}; do
	tunnels=$(( tunnels + 1 ))

	vxlan_id=$( printf "${i}\n${MY_ID}\n" | sort | xargs | tr -d ' ' )

	vxlan_id=$(( vxlan_id / 2 ))

	x=$(( vxlan_id % 2 ))

	if [ "${x}" != "0" ]; then
		my_ip=${vxlan_id}
	else
		my_ip=$(( ${vxlan_id} + 1 ))
	fi

	echo "tunnel${tunnels}: ${vxlan_id}" >> map.txt

	MY_TUN="${_s1}.${_s2}.${_s3}.${my_ip}"
	REMOTE_VXLAN_IP=$( get_vxlan_ip ${i} )
	[ -z "${REMOTE_VXLAN_IP}" ] && err 1 "Unable to determine remote VXLAN for node id $i"
	STR="ifconfig vxlan create vxlanid ${vxlan_id} vxlanlocal ${MY_VXLAN_IP} vxlanremote ${REMOTE_VXLAN_IP} inet ${MY_TUN}/31 mtu ${MTU} up"
	REMOTE_TUN="${_s1}.${_s2}.${_s3}.${i}${MY_ID}"
	echo "${STR}" >> map.txt
	echo "Remote TUN IP: ${REMOTE_TUN}" >> map.txt

	# run
	VXLAN=$( ${STR} )
	ifconfig ${VXLAN} down
	ifconfig ${VXLAN} up
	echo "${VXLAN}"
done

cat map.txt

#MY_TUN_IP="10.10.10.2/24"

#ifconfig vxlan create vxlanid 42 vxlanlocal ${MY_IP} vxlanremote ${HOST1_IP} inet ${MY_TUN_IP} mtu ${MTU} up
