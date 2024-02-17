#!/usr/bin/env bash
set -euo pipefail

_DID=
_ACCESS_JWT=

########
# _login
########
function _login() {
	local  _json="" _refresh_jwt

	rm -f ~/.bskysession

	[[ -v BSKY_HANDLE ]] || read -p 'Handle: ' BSKY_HANDLE
	[[ -v BSKY_PASSWORD ]] || {
			read -s -p 'App password: ' BSKY_PASSWORD
			echo
		}

	_json=$(curl -s -X POST https://bsky.social/xrpc/com.atproto.server.createSession \
		-H "Content-Type: application/json" \
		-d '{"identifier": "'"${BSKY_HANDLE}"'", "password": "'"${BSKY_PASSWORD}"'"}')
	if echo "${_json}" | grep -q '"error":' ; then
		echo ${_json} >&2
		echo >&2
		return 1
	fi
	read _DID _ACCESS_JWT _refresh_jwt < <(echo "${_json}" | jq -r '"\(.did) \(.accessJwt) \(.refreshJwt)"')

	echo ${_refresh_jwt} > ~/.bskysession
}

########
# _refresh_session
########
function _refresh_session() {
	local  _json _refresh_jwt

	if [[ ! -f ~/.bskysession ]]; then
		_login
		return
	fi

	_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.server.refreshSession' \
		-H 'Accept: application/json' \
		-H 'Authorization: Bearer '$(cat ~/.bskysession))
	if echo "${_json}" | grep -q '"error":' ; then
		echo ${_json} >&2
		echo >&2
		return 1
	fi
	read _DID _ACCESS_JWT _refresh_jwt < <(echo "${_json}" | jq -r '"\(.did) \(.accessJwt) \(.refreshJwt)"')

	echo ${_refresh_jwt} > ~/.bskysession
}

########
# _follows DID
# _follows HANDLE
########
function _profile() {
	local _user _json

	_user="$1"

	_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.actor.getProfile?actor='"${_user}" \
		-H 'Accept: application/json' \
		-H 'Authorization: Bearer '"${_ACCESS_JWT}")
	if echo "${_json}" | grep -q '"error":' ; then
		echo ${_json} >&2
		echo >&2
		return 1
	fi
	echo "${_json}" | jq -r '[.did, .handle] | @tsv'
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
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getFollows?actor='"${_user}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}")
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
			echo >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.follows[] | [.did, .handle] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
	done
}

########
# _feeds DID
# _feeds HANDLE
########
function _followers() {
	local _user _json _cursor=""

	_user="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getFollowers?actor='"${_user}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}")
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
		echo >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.followers[] | [.did, .handle] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
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
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.feed.getActorFeeds?actor='"${_user}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}")
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
			echo >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.feeds[] | [.uri, .displayName] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
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
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getLists?actor='"${_user}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}")
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
			echo >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.lists[] | [.uri, .purpose, .name] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
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
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getList?list='"${_listuri}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}")
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
			echo >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.items[] | [.uri, .subject.did, .subject.handle] | @tsv' | sed -e 's;.*app.bsky.graph.listitem/;;'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
	done
}

########
# DIDs | _addmember LIST_URI
########
function _addmember() {
	local _ _userdid _json

	while read _userdid _
	do
		 _json=$(curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.createRecord' \
			-H 'Content-Type: application/json' \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}" \
			--data-raw '{
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
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
			echo >&2
			return 1
		fi
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
	local _ _rkey _json

	while read _rkey _
	do
		_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.deleteRecord' \
			-H 'Content-Type: application/json' \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}" \
			--data-raw '{
			  "repo": "'"${_DID}"'",
			  "collection": "app.bsky.graph.listitem",
			  "rkey": "'"${_rkey}"'"
			}')
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
			echo >&2
			return 1
		fi
	done < <(cat -)
}

########
# _feed FEED_URI 
########
function _feed() {
	local _uri _cursor=""

	_uri="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.feed.getFeed?feed='"${_uri}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}")
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
			echo >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.feed[] | [.post.uri, .post.record.createdAt, .post.author.handle, .post.record.text] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')

		if [[ -t 1 ]] && [[ ${_cursor} != "null" ]]; then
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
	local _uri _cursor=""

	_uri="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.feed.getListFeed?list='"${_uri}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_ACCESS_JWT}")
		if echo "${_json}" | grep -q '"error":' ; then
			echo ${_json} >&2
			echo >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.feed[] | [.post.uri, .post.record.createdAt, .post.author.handle, .post.record.text] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
		
		if [[ -t 1 ]] && [[ ${_cursor} != "null" ]]; then
			read -p ": "
		else
			break
		fi
	done
}

########
# _usage
########
function _usage() {
	cat <<- EOS
		./bsky.sh login

		./bsky.sh refresh-session

		./bsky.sh profile [HANDLE]
			did handle

		./bsky.sh follows [HANDLE]
			did handle

		./bsky.sh followers [HANDLE]
			did handle

		./bsky.sh lists [HANDLE]
				uri collection name

		./bsky.sh list LIST_URI
				rkey did handle

		./bsky.sh addmember LIST_URI USER_DID
		USER_DIDs | ./bsky.sh addmember LIST_URI

		./bsky.sh delmember LIST_URI USER_DID
		USER_DIDs | ./bsky.sh delmember LIST_URI

		./bsky.sh delmember-rkey LIST_MEMBER_RKEY 
		LIST_MEMBER_RKEYs | ./bsky.sh delmember_rkey

		./bsky.sh feed FEED_URI
			uri createdAt handle text

		./bsky.sh follows [HANDLE]
			uri createdAt handle text
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
	_refresh_session || exit
fi

case "$1" in
	login)
		;;
	refresh-session)
		;;
	profile)
		_profile "$([[ $# -ge 2 ]] && echo "$2" || echo "${_DID}")"
		;;
	follows)
		_follows "$([[ $# -ge 2 ]] && echo "$2" || echo "${_DID}")"
		;;
	followers)
		_followers "$([[ $# -ge 2 ]] && echo "$2" || echo "${_DID}")"
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
	feed)
		_feed "$(if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi)"
		;;
	list-feed)
		_list_feed "$(if [[ $# -ge 2 ]]; then echo "$2"; else cat -; fi)"
		;;
	*)
		_usage
		;;
esac
