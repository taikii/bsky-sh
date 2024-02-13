# bsky.sh

`refreshJwt` export `~/.bskysession`.

This script nees jq.

```
./bsky.sh profile HANDLE
  did handle

./bsky.sh follows HANDLE
  did handle

./bsky.sh followers HANDLE
  did handle

./bsky.sh lists HANDLE
    uri collection name

./bsky.sh list LIST_URI
    rkey did handle

./bsky.sh addmember LIST_URI USER_HANDLE

./bsky.sh delmember LIST_URI USER_DID

./bsky.sh delmember_rkey LIST_MEMBER_RKEY 
```
