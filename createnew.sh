cd _posts
date=$(date "+%Y-%m-%d")
time=$(date "+%Y-%m-%d %H:%M:%S")
title=$1
filename=$date"-"$title.md
touch $filename
echo "---\r\nlayout: post\r\ntitle:  \""$title"\"\r\ndate:   "$time"\r\ncomments: true\r\ncategories:\r\n- \r\n---">$filename
cd -