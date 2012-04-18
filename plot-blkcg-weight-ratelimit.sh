#!/bin/bash

for dir
do

plot() {
data=$1
suffix=$2
gnuplot <<EOF
set xlabel "time (s)"

set size 1
set terminal pngcairo size ${width:-1000}, ${height:-600}
set terminal pngcairo size ${width:-1280}, ${height:-800}

set grid

unset grid

set output "blkcg-weight-ratelimit$suffix.png"
set ylabel "weight"
set y2label "rate (MB/s)"
set ytics nomirror
set y2tics
set logscale y2 2
plot \
     "$data" using 1:11 with points pt 6 ps 0.8 lc rgbcolor "gray" title "weight", \
     "$data" using 1:12 with  lines             lc rgbcolor "gray" title "avg weight", \
     "$data" using 1:13 with points pt 6 ps 0.8 lc rgbcolor "pink" title "async weight", \
     "$data" using 1:14 with  lines             lc rgbcolor "pink" title "avg async weight", \
     "$data" using 1:(\$9/1024)  axis x1y2 with points pt 5 ps 0.5 lw 1.5 lc rgbcolor "magenta" title "DIO rate", \
     "$data" using 1:(\$10/1024) axis x1y2 with  lines             lw 1.5 lc rgbcolor "magenta" title "avg DIO rate", \
     "$data" using 1:(\$3/1024)  axis x1y2 with points pt 1 ps 0.5 lw 1.5 lc rgbcolor "orange" title "dirty rate", \
     "$data" using 1:(\$4/1024)  axis x1y2 with  lines             lw 1.5 lc rgbcolor "orange" title "avg dirty rate", \
     "$data" using 1:(\$5/1024)  axis x1y2 with  lines             lw 1.5 lc rgbcolor "red"    title  "writeout rate", \
     "$data" using 1:(\$2/1024)  axis x1y2 with  lines             lw 1.5 lc rgbcolor "brown" title "blkcg write bps", \
     "$data" using 1:(\$6/1024)  axis x1y2 with  steps             lw 1.5 lc rgbcolor "blue" title "bdi dirty ratelimit", \
     "$data" using 1:(\$8/1024)  axis x1y2 with points pt 9 ps 0.5 lw 1.5 lc rgbcolor "blue" title "blkcg balanced dirty ratelimit", \
     "$data" using 1:(\$7/1024)  axis x1y2 with points pt 8 ps 0.5 lw 1.5 lc rgbcolor "greenyellow" title "task ratelimit"

EOF
}

cd $dir

[[ -f trace.bz2 ]] || exit

trace=trace-blkcg_dirty_ratelimit

[ -s pid ] || {
bzcat trace.bz2 | grep -F blkcg_dirty_ratelimit | awk '/(dd|tar|fio)-[0-9]+/{print $1; exit}'| sed 's/[^0-9]//g' > fio-pid
bzcat trace.bz2 | grep -F blkcg_dirty_ratelimit | awk '/<...>-[0-9]+/{print $1; exit}'| sed 's/[^0-9]//g' > more-pid
}

# dd=$(cat pid | cut -f1 -d' ')
# [[ -n "$dd" ]] || exit
for dd in $(cat pid fio-pid more-pid 2>/dev/null)
do
	bzcat trace.bz2 |\
		grep -- "-$dd \+\[" |\
		grep -qc1 -F blkcg_dirty_ratelimit && break
done
test $? = 0 || exit
test "$dd" || exit

bdi=$(bzcat trace.bz2 | grep -- "-$dd \+\[" | grep -om1 'blkcg_dirty_ratelimit: bdi .*:'|cut -f3 -d' ')
bzcat trace.bz2 | grep -E -- "-$dd +\[.* (balance_dirty_pages|bdi_dirty_ratelimit|blkcg_dirty_ratelimit): bdi $bdi " > $trace-$dd

trace_tab() {
	grep -o "[0-9.]\+: $1: .*" |\
	sed -e 's/bdi [^ ]\+//' \
	    -e 's/[^0-9.-]\+/ /g'
}

trace_tab blkcg_dirty_ratelimit < $trace-$dd > $trace

# width=1000
# width=1280
plot $trace

lines=$(wc -l $trace | cut -f1 -d' ')

# if [[ $lines -gt 600 ]]; then
# head -n 300 < $trace > $trace-rampup
# plot $trace-rampup -rampup
# 
# if [[ $lines -gt 3000 ]]; then
# tail -n 3000 < $trace > $trace-3000
# plot $trace-3000 -3000
# fi

if [[ $lines -gt 800 ]]; then

tail -n 500 $trace-$dd | trace_tab blkcg_dirty_ratelimit > $trace-500-bw-blkcg
plot $trace-500 -500
fi

rm $trace*

cd ..
done
