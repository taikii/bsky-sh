# bsky.sh

This shell calls Bluesky's API.

`refreshJwt` export `~/.bskysession`.

This script nees jq.

```
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
```
