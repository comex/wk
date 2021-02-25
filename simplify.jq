#!/usr/bin/env -S jq -f
.[].data | {
    "character": .characters,
    "readings": [.readings | sort_by(.primary == false) | .[].reading]

}
