#!/bin/bash

if [[ "${qbittorrent_running}" == "false" ]]; then

	echo "[info] Removing session lock file (if it exists)..."
	rm -f /config/qBittorrent/data/BT_backup/session.lock

	echo "[info] Attempting to start qBittorrent..."

	# run qBittorrent (daemonized, non-blocking) - note qbittorrent requires docker privileged flag
	/usr/bin/qbittorrent-nox --daemon --webui-port="${WEBUI_PORT}" --profile=/config

	# make sure process qbittorrent-nox DOES exist
	retry_count=30
	while true; do

		if ! pgrep -x "qbittorrent-nox" > /dev/null; then

			retry_count=$((retry_count-1))
			if [ "${retry_count}" -eq "0" ]; then

				echo "[warn] Wait for qBittorrent process to start aborted, too many retries"
				echo "[warn] Showing output from command before exit..."
				timeout 10 yes | /usr/bin/qbittorrent-nox --webui-port="${WEBUI_PORT}" --profile=/config ; exit 1

			else

				if [[ "${DEBUG}" == "true" ]]; then
					echo "[debug] Waiting for qBittorrent process to start..."
				fi

				sleep 1s

			fi

		else

			echo "[info] qBittorrent process started"
			break

		fi

	done

	echo "[info] Waiting for qBittorrent process to start listening on port ${WEBUI_PORT}..."

	while [[ $(netstat -lnt | awk "\$6 == \"LISTEN\" && \$4 ~ \".${WEBUI_PORT}\"") == "" ]]; do
		sleep 0.1
	done

	echo "[info] qBittorrent process listening on port ${WEBUI_PORT}"

fi

# change incoming port using the qbittorrent api - note this requires anonymous authentication via webui
# option 'Bypass authentication for clients on localhost'
if [[ "${VPN_PROV}" == "pia" && -n "${VPN_INCOMING_PORT}" ]]; then

	# identify protocol, used by curl to connect to api
	if grep -q 'WebUI\\HTTPS\\Enabled=true' '/config/qBittorrent/config/qBittorrent.conf'; then
		web_protocol="https"
	else
		web_protocol="http"
	fi

	# note -k flag required to support insecure connection (self signed certs) when https used
	
	curl -k -i -X POST -d "json={\"random_port\": false}" "${web_protocol}://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" &> /dev/null
	curl -k -i -X POST -d "json={\"listen_port\": ${VPN_INCOMING_PORT}}" "${web_protocol}://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" &> /dev/null

	# set qbittorrent port to current vpn port (used when checking for changes on next run)s
	qbittorrent_port="${VPN_INCOMING_PORT}"

fi

if [[ "${VPN_PROV}" == "custom" ]]; then

	# identify protocol, used by curl to connect to api
	if grep -q 'WebUI\\HTTPS\\Enabled=true' '/config/qBittorrent/config/qBittorrent.conf'; then
		web_protocol="https"
	else
		web_protocol="http"
	fi
	
	if [[ "${DEBUG}" == "true" ]]; then
		echo "[info] ---------------------------------------- Perfect Privacy --- qbittorrent config --- VPN INCOMING PORT value before calculating: "$VPN_INCOMING_PORT""
	fi
	
	# get internal perfect privacy IP (from interface "tun0")
	interface_name=tun0
	IPv4_ADDR=$(
	    ip a s dev $interface_name |
		awk '/inet /{gsub("/.*", "");print $2}'
	)
	
	if [[ "${DEBUG}" == "true" ]]; then
		echo "[info]  ---------------------------------------- Perfect Privacy --- qbittorrent config --- Found internal IP from dev=tun0: "$IPv4_ADDR""
	fi
	
	# convert internal IP into Port
	IFS='.' read -ra ADDR <<< "$IPv4_ADDR"
	function d2b() {
		printf "%08d" $(echo "obase=2;$1"|bc)
	}
	port_bin="$(d2b ${ADDR[2]})$(d2b ${ADDR[3]})"
	port_dec=$(printf "%04d" $(echo "ibase=2;${port_bin:4}"|bc))
	for i in 1; do
	
		# set calculated port as port variable to add to qbittorrent config 
		VPN_INCOMING_PORT=$i$port_dec
	done
	
	if [[ "${DEBUG}" == "true" ]]; then
		echo "[info] ---------------------------------------- Perfect Privacy --- qbittorrent config --- Calculated the port: "$VPN_INCOMING_PORT""
	fi
	
	# note -k flag required to support insecure connection (self signed certs) when https used
	curl -k -i -X POST -d "json={\"random_port\": false}" "${web_protocol}://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" &> /dev/null
	curl -k -i -X POST -d "json={\"listen_port\": ${VPN_INCOMING_PORT}}" "${web_protocol}://localhost:${WEBUI_PORT}/api/v2/app/setPreferences" &> /dev/null

	# set qbittorrent port to current vpn port (used when checking for changes on next run)s
	qbittorrent_port="${VPN_INCOMING_PORT}"

fi


# set qbittorrent ip to current vpn ip (used when checking for changes on next run)
qbittorrent_ip="${vpn_ip}"
