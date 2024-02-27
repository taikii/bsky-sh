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
		-d @- <<< '{"identifier": "'"${BSKY_HANDLE}"'", "password": "'"${BSKY_PASSWORD}"'"}')
	if echo "${_json}" | grep -q '"error":' ; then
		echo "${_json}" >&2
		return 1
	fi
	read _DID _ACCESS_JWT _refresh_jwt < <(jq -r '"\(.did) \(.accessJwt) \(.refreshJwt)"' <<< "${_json}")

	cat <<< "${_refresh_jwt}" > ~/.bskysession
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
		-K- <<< "Header = \"Authorization: Bearer $(cat ~/.bskysession)\"")
	if echo "${_json}" | grep -q '"error":' ; then
		echo "${_json}" >&2
		return 1
	fi
	read _DID _ACCESS_JWT _refresh_jwt < <(jq -r '"\(.did) \(.accessJwt) \(.refreshJwt)"' <<< "${_json}")

	cat <<< "${_refresh_jwt}" > ~/.bskysession
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
		-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
	if echo "${_json}" | grep -q '"error":' ; then
		echo "${_json}" >&2
		return 1
	fi
	echo "${_json}" | jq -r '[.did, .handle, .displayName, .description] | @tsv'
}

########
# _search_user QUERY
########
function _search_user() {
	local _q _json _cursor=""

	_q="$1"

	while [[ ${_cursor} != "null" ]]
	do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.actor.searchActors?q='"$(echo "${_q}" | jq -Rr @uri )"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.actors[] | [.did, .handle, .displayName, .description] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
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
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getFollows?actor='"${_user}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.follows[] | [.did, .handle, .displayName, .description] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
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
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getFollowers?actor='"${_user}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.followers[] | [.did, .handle, .displayName, .description] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
	done
}

########
# _blocks
########
function _blocks() {
	local _json _cursor=""

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getBlocks?cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.blocks[] | [.viewer.blocking, .did, .handle, .displayName, .description] | @tsv' | sed -e 's;.*app.bsky.graph.block/;;'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
	done
}

########
# _mutes
########
function _mutes() {
	local _json _cursor=""

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getMutes?cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.mutes[] | [.did, .handle, .displayName, .description] | @tsv'
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
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
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
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
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
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.items[] | [.uri, .subject.did, .subject.handle, .subject.displayName, .subject.description] | @tsv' | sed -e 's;.*app.bsky.graph.listitem/;;'
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
			-K- \
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
			}' \
			<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi

		# echo rkey[\t]did
		echo -e "$(echo "${_json}" | jq -r '.uri' | sed -e 's;.*/;;')\t${_userdid}"
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
			-K- \
			--data-raw '{
				"repo": "'"${_DID}"'",
				"collection": "app.bsky.graph.listitem",
				"rkey": "'"${_rkey}"'"
			}' \
			<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
	done < <(cat -)
}

########
# DIDs | _block
########
function _block() {
	local _ _userdid _json

	while read _userdid _
	do
		_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.createRecord' \
			-H 'Content-Type: application/json' \
			-H 'Accept: application/json' \
			-K- \
			--data-raw '{
				"repo": "'"${_DID}"'",
				"collection": "app.bsky.graph.block",
				"validate": true,
				"record": {
					"$type": "app.bsky.graph.block",
					"subject": "'"${_userdid}"'",
					"createdAt": "'"$(date '+%Y-%m-%dT%H:%M:%S' --utc)Z"'"
				}
			}' \
			<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi

		# echo rkey[\t]did
		echo -e "$(echo "${_json}" | jq -r '.uri' | sed -e 's;.*/;;')\t${_userdid}"
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
	local _ _rkey _json

	while read _rkey _
	do
		_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.deleteRecord' \
			-H 'Content-Type: application/json' \
			-H 'Accept: application/json' \
			-K- \
			--data-raw '{
				"repo": "'"${_DID}"'",
				"collection": "app.bsky.graph.block",
				"rkey": "'"${_rkey}"'"
			}' \
			<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
	done < <(cat -)
}

########
# DIDs | _mute
########
function _mute() {
	local _ _userdid _json

	while read _userdid _
	do
		_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/app.bsky.graph.muteActor' \
			-H 'Content-Type: application/json' \
			-H 'Accept: application/json' \
			-K- \
			--data-raw '{
				"actor": "'"${_userdid}"'"
			}' \
			<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
	done < <(cat -)
}

########
# DIDs | _unmute
########
function _unmute() {
	local _ _userdid _json

	while read _userdid _
	do
		_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/app.bsky.graph.unmuteActor' \
			-H 'Content-Type: application/json' \
			-H 'Accept: application/json' \
			-K- \
			--data-raw '{
				"actor": "'"${_userdid}"'"
			}' \
			<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
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
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.feed[] | [.post.uri, .post.record.createdAt, .post.author.handle, .post.record.text] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')

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
	local _uri _cursor=""

	_uri="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.feed.getListFeed?list='"${_uri}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.feed[] | [.post.uri, .post.record.createdAt, .post.author.handle, .post.record.text] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')
		
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
	local _user _cursor=""

	_user="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.feed.getAuthorFeed?actor='"${_user}"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.feed[] | [.post.uri, .post.record.createdAt, .post.author.handle, .post.record.text] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')

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
	local _q _cursor=""

	_q="$1"

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.feed.searchPosts?q='"$(echo "${_q}" | jq -Rr @uri )"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		echo "${_json}" | jq -r '.posts[] | [.uri, .record.createdAt, .author.handle, .record.text] | @tsv'
		_cursor=$(echo "${_json}" | jq -r '.cursor')

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
	local _json

	_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.createRecord' \
		-H 'Content-Type: application/json' \
		-H 'Accept: application/json' \
		-K- \
		--data-raw '{
			"repo": "'"${_DID}"'",
			"collection": "app.bsky.feed.post",
			"validate": true,
			"record": {
				"$type": "app.bsky.feed.post",
				"text": "'"$(cat - | sed -z -e 's/\n$//' -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' -e 's/\r//g')"'",
				"createdAt": "'"$(date '+%Y-%m-%dT%H:%M:%S' --utc)Z"'"
			}
		}' \
		<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
	if echo "${_json}" | grep -q '"error":' ; then
		echo "${_json}" >&2
		return 1
	fi
}

########
# _feed_generator AT_URI
########
function _feed_generator() {
	local _aturi _json

	_aturi="$1"
	echo $_aturi

	_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.feed.getFeedGenerator?feed='"${_aturi}" \
		-H 'Accept: application/json' \
		-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
	if echo "${_json}" | grep -q '"error":' ; then
		echo "${_json}" >&2
		return 1
	fi
	[[ -n ${_json} ]] || return 0
	# echo "${_json}" | jq -r '.items[] | [.uri, .subject.did, .subject.handle] | @tsv' | sed -e 's;.*app.bsky.graph.listitem/;;'
	echo "${_json}" | jq
}

########
# DESCRIPTION | _new_feed_generator ENDPOINT DISPLAY_NAME
########
function _new_feed_generator() {
	local _json

	_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.createRecord' \
		-H 'Content-Type: application/json' \
		-H 'Accept: application/json' \
		-K- \
		--data-raw '{
			"repo": "'"${_DID}"'",
			"collection": "app.bsky.feed.generator",
			"validate": true,
			"record": {
				"$type": "app.bsky.feed.generator",
				"did": "did:web:'"$1"'",
				"displayName": "'"$(echo $2 | sed -z -e 's/\n$//' -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' -e 's/\r//g')"'",
				"description": "'"$(cat - | sed -z -e 's/\n$//' -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' -e 's/\r//g')"'",
				"createdAt": "'"$(date '+%Y-%m-%dT%H:%M:%S' --utc)Z"'"
			}
		}' \
		<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
	if echo "${_json}" | grep -q '"error":' ; then
		echo "${_json}" >&2
		return 1
	fi
	echo "${_json}"
}

########
# _del_feed_generator RKEY
########
function _del_feed_generator() {
	local _json

	_json=$(curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.deleteRecord' \
		-H 'Content-Type: application/json' \
		-H 'Accept: application/json' \
		-K- \
		--data-raw '{
			"repo": "'"${_DID}"'",
			"collection": "app.bsky.feed.generator",
			"rkey": "'"$1"'"
		}' \
		<<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
	if echo "${_json}" | grep -q '"error":' ; then
		echo "${_json}" >&2
		return 1
	fi
	echo "${_json}"
}

########
# _list_records USER_DID COLLECTION
########
function _list_records() {
	local _json _cursor=""

	while [[ ${_cursor} != "null" ]]
		do
		_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/com.atproto.repo.listRecords?repo='"$1"'&collection='"$2"'&cursor='"${_cursor}" \
			-H 'Accept: application/json' \
			-K- <<< "Header = \"Authorization: Bearer ${_ACCESS_JWT}\"")
		if echo "${_json}" | grep -q '"error":' ; then
			echo "${_json}" >&2
			return 1
		fi
		[[ -n ${_json} ]] || return 0
		_cursor=$(echo "${_json}" | jq -r '.cursor')

		echo "${_json}" | jq -c ".records[]"
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
	feed-generator)
		_feed_generator $2
		;;
	new-feed-generator)
		cat - | _new_feed_generator "$2" "$3"
		;;
	del-feed-generator)
		_del_feed_generator "$2"
		;;
	list-records)
		_list_records "$2" "$3"
		;;
	*)
		_usage
		;;
esac
