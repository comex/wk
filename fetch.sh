# lol
set -e
KEY=a93cae63d929a4b554b98e58b3920681
wget -O user-info.json https://www.wanikani.com/api/user/$KEY/user-information
level=$(python -c 'import json; print json.load(open("user-info.json"))["user_information"]["level"]')
incr=5
echo "level $level"
for start in $(seq 1 $incr $level); do
    end=$((start+incr-1))
    if [ $level -lt $end ]; then end=$level; fi
    comma=$(seq -s ',' $start $end | sed 's/,$//')
    wget -O vocabulary-$start.json https://www.wanikani.com/api/user/$KEY/vocabulary/$comma
    wget -O kanji-$start.json https://www.wanikani.com/api/user/$KEY/kanji/$comma
    wget -O radicals-$start.json https://www.wanikani.com/api/user/$KEY/radicals/$comma
done

for x in vocabulary kanji radicals; do
    python -c 'import json, glob; print json.dumps([w for l in map(json.load, map(open, glob.glob("'$x'-[0-9]*.json"))) for w in l["requested_information"]])' > $x.json
    rm ./$x-[0-9]*.json
done

