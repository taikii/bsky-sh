#!/usr/bin/env bash
set -eo pipefail

_BSKY_SESSION_DID=
_BSKY_ACCESS_JWT=

function _reflesh_session() {
	local _handle _password _refresh_jwt

	if [[ -f ~/.bskysession ]]; then
		read _BSKY_SESSION_DID _BSKY_ACCESS_JWT _refresh_jwt < <( \
				curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.server.refreshSession' \
					-H 'Accept: application/json' \
					-H 'Authorization: Bearer '$(cat ~/.bskysession) \
					| jq -r '"\(.did) \(.accessJwt) \(.refreshJwt)"') || return
	else
		read -p 'Handle: ' _handle
		read -s -p 'App password: ' _password
		echo

		read _BSKY_SESSION_DID _BSKY_ACCESS_JWT _refresh_jwt < <( \
			curl -s -X POST https://bsky.social/xrpc/com.atproto.server.createSession \
				-H "Content-Type: application/json" \
				-d '{"identifier": "'"${_handle}"'", "password": "'"${_password}"'"}' \
				| jq -r '"\(.did) \(.accessJwt) \(.refreshJwt)"') || return
	fi

	echo ${_refresh_jwt} > ~/.bskysession
}

function _profile() {
	local _ _user

	while read _user _
	do
		curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.actor.getProfile?actor='"${_user}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_BSKY_ACCESS_JWT}" \
			| jq -r '[.did, .handle] | @tsv'
	done < <(cat -)
}

function _lists() {
	local _ _user

	while read _user _
	do
		curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getLists?actor='"${_user}" \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_BSKY_ACCESS_JWT}" \
			| jq -r '.lists[] | [.uri, .purpose, .name] | @tsv'
	done < <(cat -)
}

function _list() {
	local _ _user _json _cursor

	while read _user _
	do
		while [[ ${_cursor} != "null" ]]
			do
			_json=$(curl -s -L -X GET 'https://bsky.social/xrpc/app.bsky.graph.getList?list='"${_user}"'&cursor='"${_cursor}" \
				-H 'Accept: application/json' \
				-H 'Authorization: Bearer '"${_BSKY_ACCESS_JWT}") || return
			echo "${_json}" | jq -r '.items[] | [.uri, .subject.did, .subject.handle] | @tsv' | sed -e 's;.*app.bsky.graph.listitem/;;' || return
			_cursor=$(echo "${_json}" | jq -r '.cursor') || return
		done
	done < <(cat -)
}

function _addmember() {
	local _ _userdid

	while read _userdid _
	do
		curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.createRecord' \
			-H 'Content-Type: application/json' \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_BSKY_ACCESS_JWT}" \
			--data-raw '{
			  "repo": "'"${_BSKY_SESSION_DID}"'",
			  "collection": "app.bsky.graph.listitem",
			  "validate": true,
			  "record": {
			    "$type": "app.bsky.graph.listitem",
			    "subject": "'"${_userdid}"'",
			    "list": "'"$1"'",
			    "createdAt": "'"$(date '+%Y-%m-%dT%H:%M:%S' --utc)Z"'"
			  }
			}' || return
	done < <(cat -)
}

function _delmember() {
	join -t $'\t' -1 2 -2 1 -o 1.1 \
		<(echo "$1" | _list | sort -t $'\t' -k 2) \
		<(cat - | sort) \
		| _delmember_rkey
}

function _delmember_rkey() {
	local _ _rkey

	while read _rkey _
	do
		curl -s -L -X POST 'https://bsky.social/xrpc/com.atproto.repo.deleteRecord' \
			-H 'Content-Type: application/json' \
			-H 'Accept: application/json' \
			-H 'Authorization: Bearer '"${_BSKY_ACCESS_JWT}" \
			--data-raw '{
			  "repo": "'"${_BSKY_SESSION_DID}"'",
			  "collection": "app.bsky.graph.listitem",
			  "rkey": "'"${_rkey}"'"
			}' || return
	done < <(cat -)
}

function _help() {
	cat README.md
}

_reflesh_session || exit 1

case "$1" in
	profile)
		if [[ $# -eq 2 ]]; then
			echo "$2"
		else
			cat -
		fi |_profile
		;;
	lists)
		if [[ $# -eq 2 ]]; then
			echo "$2"
		else
			cat -
		fi |_profile | cut -f 1 | _lists
		;;
	list)
		if [[ $# -eq 2 ]]; then
			echo "$2"
		else
			cat -
		fi | _list
		;;
	addmember)
		if [[ $# -eq 3 ]]; then
			echo "$3"
		else
			cat -
		fi | _addmember "$2"
		;;
	delmember)
		if [[ $# -eq 3 ]]; then
			echo "$3"
		else
			cat -
		fi | _delmember "$2"
		;;
	delmember_rkey)
		if [[ $# -eq 2 ]]; then
			echo "$2"
		else
			cat -
		fi | _delmember_rkey
		;;
	*)
		_help
		;;
esac

