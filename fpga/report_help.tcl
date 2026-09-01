foreach command {report_design_analysis report_utilization report_high_fanout_nets report_timing} {
    puts "===== $command ====="
    puts [help $command -syntax]
}
exit
