onbreak {quit -f}
onerror {quit -f}

vsim -lib xil_defaultlib DB_leading_edge_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

do {wave.do}

view wave
view structure
view signals

do {DB_leading_edge.udo}

run -all

quit -force
