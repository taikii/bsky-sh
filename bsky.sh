#!/usr/bin/env bash
set -euo pipefail

_REFRESH_JWT=
_ACCESS_JWT=
_DID=
_ENDPOINT='https://public.api.bsky.app'

_SERVICEENDPOINT='https://bsky.social'

########
# _get_session
########
function _get_session() {
	if [[ ! -f ~/.bskysession ]]; then
		_login
	fi

	read _REFRESH_JWT _ACCESS_JWT _DID _ENDPOINT < ~/.bskysession

	if [[ -z ${_REFRESH_JWT} ]]; then
		_login
	elif [[ -z ${_ACCESS_JWT} ]]; then
		_refresh_session
	fi
}

########
# _login
########
function _login() {
	local  _json

	rm -f ~/.bskysession

	[[ -v BSKY_HANDLE ]] || read -p 'Handle: ' BSKY_HANDLE
	[[ -v BSKY_PASSWORD ]] || {
			read -s -p 'App password: ' BSKY_PASSWORD
			echo
		}

	_json=$(curl -s -X POST "${_SERVICEENDPOINT}"'/xrpc/com.atproto.server.createSession' \
		-H "Content-Type: application/json" \
		-d @- <<< '{"identifier": "'"${BSKY_HANDLE}"'", "password": "'"${BSKY_PASSWORD}"'"}')
	if grep -q '"error":' <<< "${_json}" ; then
		echo "${_json}" >&2
		return 1
	fi

	jq -r '"\(.refreshJwt) \(.accessJwt) \(.did) \(.didDoc.service[0].serviceEndpoint)"' <<< "${_json}" > ~/.bskysession
	read _REFRESH_JWT _ACCESS_JWT _DID _ENDPOINT < ~/.bskysession
}

########
# _refresh_session
########
function _refresh_session() {
	local  _json
	if [[ ! -f ~/.bskysession ]]; then
		_login
		return
	fi

	_json=$(curl -s -L -X POST "${_SERVICEENDPOINT}"'/xrpc/com.atproto.server.refreshSession' \
		-H 'Accept: application/json' \
		-K- <<< "Header = \"Authorization: Bearer ${_REFRESH_JWT}\"")
	if grep -q '"error":' <<< "${_json}" ; then
		echo "${_json}" >&2
		return 1
	fi

	jq -r '"\(.refreshJwt) \(.accessJwt) \(.did) \(.didDoc.service[0].serviceEndpoint)"' <<< "${_json}" > ~/.bskysession
	read _REFRESH_JWT _ACCESS_JWT _DID _ENDPOINT < ~/.bskysession
}

########
# _httpget URI
########
function _httpget() {
	local _json _uri _stdin=""

	_uri="$1"

	_json=$(curl -s -L -X GET "${_uri}" \
		-H 'Accept: application/json' \
		-K- \
		<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
	if grep -q '"error":"ExpiredToken"' <<< "${_json}" ; then
		if [[ ${FUNCNAME[0]} == ${FUNCNAME[1]} ]]; then
			echo "${_json}" >&2
			return 1
		else
			_refresh_session
			${FUNCNAME[0]} "$@"
			return
		fi
	elif grep -q '"error":' <<< "${_json}" ; then
		echo "${_json}" >&2
		return 1
	fi

	if [[ -n ${_json} ]]; then
		echo "${_json}"
	fi
}

########
# _httppost URI DATA
########
function _httppost() {
	local _json _uri _data _stdin=""

	_uri="$1"
	_data="$2"

	_json=$(curl -s -L -X POST "${_uri}" \
		-H 'Content-Type: application/json' \
		-H 'Accept: application/json' \
		-K- \
		--data-raw "${_data}" \
		<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
	if grep -q '"error":"ExpiredToken"' <<< "${_json}" ; then
		if [[ ${FUNCNAME[0]} == ${FUNCNAME[1]} ]]; then
			echo "${_json}" >&2
			return 1
		else
			_refresh_session
			${FUNCNAME[0]} "$@"
			return
		fi
	elif grep -q '"error":' <<< "${_json}" ; then
		echo "${_json}" >&2
		return 1
	fi

	if [[ -n ${_json} ]]; then
		echo "${_json}"
	fi
}

########
# _follows DID
# _follows HANDLE
########
function _profile() {
	local _json
	_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.actor.getProfile?actor='"$1")
	jq -r '[.did, .handle, .displayName, .description] | @tsv' <<< "${_json}"
}

########
# _search_user QUERY
########
function _search_user() {
	local _q _json _cursor=""

	_q="$1"

	while [[ ${_cursor} != "null" ]]
	do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.actor.searchActors?q='"$(jq -Rr '@uri' <<< "${_q}")"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.actors[] | [.did, .handle, .displayName, .description] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")
	done
}

########
# _follows DID
# _follows HANDLE
########
function _follows() {
	local _user _json _cursor=""

	_user="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.graph.getFollows?actor='"${_user}"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.follows[] | [.did, .handle, .displayName, .description] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")
	done
}

########
# _followers DID
# _followers HANDLE
########
function _followers() {
	local _user _json _cursor=""

	_user="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.graph.getFollowers?actor='"${_user}"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.followers[] | [.did, .handle, .displayName, .description] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")
	done
}

########
# _blocks
########
function _blocks() {
	local _json _cursor=""

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.graph.getBlocks?cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.blocks[] | [.viewer.blocking, .did, .handle, .displayName, .description] | @tsv' <<< "${_json}" | sed -e 's;.*app.bsky.graph.block/;;'
		_cursor=$(jq -r '.cursor' <<< "${_json}")
	done
}

########
# _mutes
########
function _mutes() {
	local _json _cursor=""

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.graph.getMutes?cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.mutes[] | [.did, .handle, .displayName, .description] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")
	done
}

########
# _feeds DID
########
function _feeds() {
	local _user _json _cursor=""

	if [[ $1 == "did:"* ]]; then
		_user="$1"
	else
		_user="$(_profile "$1" | cut -f 1)"
	fi

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.feed.getActorFeeds?actor='"${_user}"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.feeds[] | [.uri, .displayName] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")
	done
}

########
# _list DID
########
function _lists() {
	local _user _json _cursor=""

	if [[ $1 == "did:"* ]]; then
		_user="$1"
	else
		_user="$(_profile "$1" | cut -f 1)"
	fi

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.graph.getLists?actor='"${_user}"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.lists[] | [.uri, .purpose, .name] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")
	done
}

########
# _list LIST_URI
########
function _list() {
	local _listuri _json _cursor=""

	_listuri="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.graph.getList?list='"${_listuri}"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.items[] | [.uri, .subject.did, .subject.handle, .subject.displayName, .subject.description] | @tsv' <<< "${_json}" | sed -e 's;.*app.bsky.graph.listitem/;;'
		_cursor=$(jq -r '.cursor' <<< "${_json}")
	done
}

########
# DIDs | _addmember LIST_URI
########
function _addmember() {
	local _userdid _json
	while read _userdid _
	do
		_json=$(_httppost "${_ENDPOINT}"'/xrpc/com.atproto.repo.createRecord' '{
				"repo": "'"${_DID}"'",
				"collection": "app.bsky.graph.listitem",
				"validate": true,
				"record": {
					"$type": "app.bsky.graph.listitem",
					"subject": "'"${_userdid}"'",
					"list": "'"$1"'",
					"createdAt": "'"$(date '+%Y-%m-%dT%H:%M:%S' --utc)Z"'"
				}
			}')

		# echo rkey[\t]did
		echo -e "$(jq -r '.uri' <<< "${_json}" | sed -e 's;.*/;;')\t${_userdid}"
	done < <(cat -)
}

########
# DIDs | _delmember LIST_URI
########
function _delmember() {
	join -t $'\t' -1 2 -2 1 -o 1.1 \
		<(_list "$1" | sort -t $'\t' -k 2) \
		<(cat - | sort) \
		| _delmember_rkey
}

########
# RKEYs | _delmember_rkey
########
function _delmember_rkey() {
	local _rkey

	while read _rkey _
	do
		_httppost "${_ENDPOINT}"'/xrpc/com.atproto.repo.deleteRecord' '{
				"repo": "'"${_DID}"'",
				"collection": "app.bsky.graph.listitem",
				"rkey": "'"${_rkey}"'"
			}'
	done < <(cat -)
}

########
# DIDs | _block
########
function _block() {
	local _userdid _json

	while read _userdid _
	do
		_json=$(_httppost "${_ENDPOINT}"'/xrpc/com.atproto.repo.createRecord' '{
				"repo": "'"${_DID}"'",
				"collection": "app.bsky.graph.block",
				"validate": true,
				"record": {
					"$type": "app.bsky.graph.block",
					"subject": "'"${_userdid}"'",
					"createdAt": "'"$(date '+%Y-%m-%dT%H:%M:%S' --utc)Z"'"
				}
			}')

		# echo rkey[\t]did
		echo -e "$(jq -r '.uri' <<< "${_json}" | sed -e 's;.*/;;')\t${_userdid}"
	done < <(cat -)
}

########
# DIDs | _unblock
########
function _unblock() {
	join -t $'\t' -1 2 -2 1 -o 1.1 \
		<(_blocks | sort -t $'\t' -k 2) \
		<(cat - | sort) \
		| _unblock_rkey
}

########
# RKEYs | _unblock_rkey
########
function _unblock_rkey() {
	local _rkey _json

	while read _rkey _
	do
		_httppost "${_ENDPOINT}"'/xrpc/com.atproto.repo.deleteRecord' '{
				"repo": "'"${_DID}"'",
				"collection": "app.bsky.graph.block",
				"rkey": "'"${_rkey}"'"
			}'
	done < <(cat -)
}

########
# DIDs | _mute
########
function _mute() {
	local _userdid

	while read _userdid _
	do
		_httppost "${_ENDPOINT}"'/xrpc/app.bsky.graph.muteActor' '{
				"actor": "'"${_userdid}"'"
			}'
	done < <(cat -)
}

########
# DIDs | _unmute
########
function _unmute() {
	local _userdid _json

	while read _userdid _
	do
		_httppost "${_ENDPOINT}"'/xrpc/app.bsky.graph.unmuteActor' '{
				"actor": "'"${_userdid}"'"
			}'
	done < <(cat -)
}

########
# _feed FEED_URI 
########
function _feed() {
	local _uri _json _cursor=""

	_uri="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.feed.getFeed?feed='"${_uri}"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.feed[] | [.post.uri, .post.record.createdAt, .post.author.handle, .post.record.text] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")

		if [[ -t 0 ]] && [[ ${_cursor} != "null" ]]; then
			read -p ": "
		else
			break
		fi
	done
}

########
# _list_feed LIST_FEED_URI 
########
function _list_feed() {
	local _uri _json _cursor=""

	_uri="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.feed.getListFeed?list='"${_uri}"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.feed[] | [.post.uri, .post.record.createdAt, .post.author.handle, .post.record.text] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")
		
		if [[ -t 0 ]] && [[ ${_cursor} != "null" ]]; then
			read -p ": "
		else
			break
		fi
	done
}

########
# _user_feed HANDLE 
########
function _user_feed() {
	local _user _json _cursor=""

	_user="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.feed.getAuthorFeed?actor='"${_user}"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.feed[] | [.post.uri, .post.record.createdAt, .post.author.handle, .post.record.text] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")

		if [[ -t 0 ]] && [[ ${_cursor} != "null" ]]; then
			read -p ": "
		else
			break
		fi
	done
}

########
# _search_posts QUERY 
########
function _search_posts() {
	local _q _json _cursor=""

	_q="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(_httpget "${_ENDPOINT}"'/xrpc/app.bsky.feed.searchPosts?q='"$(jq -Rr '@uri' <<< "${_q}")"'&cursor='"${_cursor}")
		[[ -n ${_json} ]] || return 0
		jq -r '.posts[] | [.uri, .record.createdAt, .author.handle, .record.text] | @tsv' <<< "${_json}"
		_cursor=$(jq -r '.cursor' <<< "${_json}")

		if [[ -t 0 ]] && [[ ${_cursor} != "null" ]]; then
			read -p ": "
		else
			break
		fi
	done
}

########
# TEXT | _post
########
function _post() {
	local _msg _facets

	# Trimming
	_msg=$(cat - | sed -z -e 's/\n$//' -e 's/\r//g')

	_facets=$(awk -v 'RS=' --characters-as-bytes '
		{
			msg = $0
			start = 0
			while (match(msg, /https?:\/\/[-0-9a-zA-Z+&@#\/%?=~_|!:,.;\(\)]+/)) {
				printf "{\"index\": {\"byteStart\": %s, \"byteEnd\": %s}, \"features\": [{\"$type\": \"app.bsky.richtext.facet#link\", \"uri\": \"%s\"}]},", start + RSTART - 1, start + RSTART + RLENGTH - 1, substr(msg, RSTART, RLENGTH)
				msg = substr(msg, RSTART + RLENGTH)
				start = start + RSTART + RLENGTH - 1
			}

			msg = $0
			start = 0
			while (match(msg, /@[0-9a-zA-Z.]+/)) {
				"'$(readlink -f $0)' profile "substr(msg, RSTART + 1, RLENGTH - 1) | getline did
				did=substr(did, 1, index(did, "\t") - 1)
				printf "{\"index\": {\"byteStart\": %s, \"byteEnd\": %s}, \"features\": [{\"$type\": \"app.bsky.richtext.facet#mention\", \"did\": \"%s\"}]},", start + RSTART - 1, start + RSTART + RLENGTH - 1, did
				msg = substr(msg, RSTART + RLENGTH)
				start = start + RSTART + RLENGTH - 1
			}

			msg = $0
			start = 0
			while (match(msg, /\B#\S+/)) {
				printf "{\"index\": {\"byteStart\": %s, \"byteEnd\": %s}, \"features\": [{\"$type\": \"app.bsky.richtext.facet#tag\", \"tag\": \"%s\"}]},", start + RSTART - 1, start + RSTART + RLENGTH - 1, substr(msg, RSTART + 1, RLENGTH - 1)
				msg = substr(msg, RSTART + RLENGTH)
				start = start + RSTART + RLENGTH - 1
			}
		}' <<< ${_msg} | sed -e 's/,$//g');

	# Escape
	_msg=$(sed -z -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' <<< "${_msg}")

	_httppost "${_ENDPOINT}"'/xrpc/com.atproto.repo.createRecord' '{
			"repo": "'"${_DID}"'",
			"collection": "app.bsky.feed.post",
			"validate": true,
			"record": {
				"$type": "app.bsky.feed.post",
				"text": "'"${_msg}"'",
				"createdAt": "'"$(date '+%Y-%m-%dT%H:%M:%S' --utc)Z"'",
				"facets": [
					'"${_facets}"'
				]
			}
		}'
}

########
# _usage
########
function _usage() {
	cat <<- EOS
		./bsky.sh login

		./bsky.sh refresh-session

		./bsky.sh profile [HANDLE]
			did handle displayName description

		./bsky.sh search-user QUERY
			did handle displayName description

		./bsky.sh follows [HANDLE]
			did handle displayName description

		./bsky.sh followers [HANDLE]
			did handle displayName description
	
		./bsky.sh blocks
			rkey did handle displayName description

		./bsky.sh mutes
			did handle displayName description

		./bsky.sh lists [HANDLE]
			uri collection name

		./bsky.sh list LIST_URI
			rkey did handle displayName description

		./bsky.sh addmember LIST_URI USER_DID
		USER_DIDs | ./bsky.sh addmember LIST_URI

		./bsky.sh delmember LIST_URI USER_DID
		USER_DIDs | ./bsky.sh delmember LIST_URI

		./bsky.sh delmember-rkey LIST_MEMBER_RKEY 
		LIST_MEMBER_RKEYs | ./bsky.sh delmember_rkey

		./bsky.sh feed FEED_URI
			uri createdAt handle text

		./bsky.sh list-feed LIST_URI
			uri createdAt handle text

		./bsky.sh feed FEED_URI
			uri createdAt handle text

		./bsky.sh user-feed HANDLE
			uri createdAt handle text

		./bsky.sh search-posts QUERY
			uri createdAt handle text

		./bsky.sh post TEXT
		TEXT | ./bsky.sh post
	EOS
}

if [[ $# -eq 0 ]]; then
	_usage
	exit 0
fi

if [[ $1 == "login" ]]; then
	_login
	exit
else
	_get_session || exit
fi

case "$1" in
	login)
		_login
		;;
	refresh-session)
		_refresh_session
		;;
	profile)
		_profile "$([[ $# -ge 2 ]] && echo "$2" || echo "${_DID}")"
		;;
	search-user)
		_search_user "$2"
		;;
	follows)
		_follows "$([[ $# -ge 2 ]] && echo "$2" || echo "${_DID}")"
		;;
	followers)
		_followers "$([[ $# -ge 2 ]] && echo "$2" || echo "${_DID}")"
		;;
	mutes)
		_mutes
		;;
	blocks)
		_blocks
		;;
	feeds)
		_feeds "$([[ $# -ge 2 ]] && echo "$2" || echo "${_DID}")"
		;;
	lists)
		_lists "$([[ $# -ge 2 ]] && echo "$2" || echo "${_DID}")"
		;;
	list)
		_list "$2"
		;;
	addmember)
		if [[ $# -ge 3 ]]; then echo "$3"; else cat -; fi | _addmember "$2"
		;;
	delmember)
		if [[ $# -ge 3 ]]; then echo "$3"; else cat -; fi | _delmember "$2"
		;;
	delmember-rkey)
		if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi | _delmember_rkey
		;;
	block)
		if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi | _block
		;;
	unblock)
		if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi | _unblock
		;;
	unblock-rkey)
		if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi | _unblock_rkey
		;;
	mute)
		if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi | _mute
		;;
	unmute)
		if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi | _unmute
		;;
	feed)
		_feed "$2"
		;;
	list-feed)
		_list_feed "$2"
		;;
	user-feed)
		_user_feed "$2"
		;;
	search)
		_search_posts "$2"
		;;
	post)
		if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi | _post
		;;
	*)
		_usage
		;;
esac
