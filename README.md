# bsky.sh

This shell calls Bluesky's API.

`refreshJwt` export `~/.bskysession`.

This script nees jq.

```
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
  rdkey did handle displayName description

./bsky.sh mutes
  did handle displayName description

./bsky.sh lists [HANDLE]
  uri collection name

./bsky.sh list LIST_URI
  rkey did handle displayName description

./bsky.sh addmember LIST_URI USER_DID
USER_DIDs | ./bsky.sh addmember LIST_URI
  rkey did

./bsky.sh delmember LIST_URI USER_DID
USER_DIDs | ./bsky.sh delmember LIST_URI

./bsky.sh delmember-rkey LIST_MEMBER_RKEY 
LIST_MEMBER_RKEYs | ./bsky.sh delmember_rkey

./bsky.sh block USER_DID 
USER_DIDs | ./bsky.sh block
  rkey did

./bsky.sh unblock USER_DID 
USER_DIDs | ./bsky.sh unblock

./bsky.sh unblock-rkey RKEY 
RKEYs | ./bsky.sh unblock-rkey

./bsky.sh mute USER_DID 
USER_DIDs | ./bsky.sh mute

./bsky.sh unmute USER_DID 
USER_DIDs | ./bsky.sh unmute

./bsky.sh feed FEED_URI
  uri createdAt handle text

./bsky.sh list-feed LIST_URI
  uri createdAt handle text

./bsky.sh user-feed HANDLE
  uri createdAt handle text

./bsky.sh post TEXT
TEXT | ./bsky.sh post
```
