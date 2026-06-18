`timescale 1 ns / 1 ps

module tb_leading_edge_core_csv;

    localparam integer MODE_LINEAR = 0;
    localparam integer MODE_EXP    = 1;
    localparam integer MODE_LOG    = 2;

    reg clk;
    reg rst_n;
    reg start;
    reg [1:0] mode_sel;
    reg signed [31:0] t1;
    reg signed [31:0] a1;
    reg signed [31:0] t2;
    reg signed [31:0] a2;
    reg signed [31:0] t3;
    reg signed [31:0] a3;
    reg signed [31:0] threshold;

    wire signed [31:0] t0_est;
    wire signed [31:0] amax_est;
    wire valid;
    wire overflow;

    integer csv_fd;
    integer input_fd;
    integer scan_count;
    integer event_count;
    integer pass_count;
    integer fail_count;
    reg [8*512-1:0] header_line;
    real csv_t1;
    real csv_a1;
    real csv_t2;
    real csv_a2;
    real csv_t3;
    real csv_a3;
    real csv_true_t0;
    real csv_true_amax;
    real csv_sigma_ns;
    real csv_tau_ns;
    real csv_threshold;
    real csv_charge;
    real csv_true_t_leading;
    real csv_true_t_trailing;
    real csv_true_tot;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100 MHz
    end

    leading_edge_core dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .mode_sel  (mode_sel),
        .t1        (t1),
        .a1        (a1),
        .t2        (t2),
        .a2        (a2),
        .t3        (t3),
        .a3        (a3),
        .threshold (threshold),
        .t0_est    (t0_est),
        .amax_est  (amax_est),
        .valid     (valid),
        .overflow  (overflow)
    );

    function signed [31:0] q16;
        input real value;
        real scaled;
        begin
            scaled = value * 65536.0;
            if (scaled >= 0.0)
                q16 = $rtoi(scaled + 0.5);
            else
                q16 = $rtoi(scaled - 0.5);
        end
    endfunction

    function real fq16;
        input signed [31:0] value;
        begin
            fq16 = $itor(value) / 65536.0;
        end
    endfunction

    function real abs_real;
        input real value;
        begin
            abs_real = (value < 0.0) ? -value : value;
        end
    endfunction

    function real expected_t0;
        input integer mode;
        input real rt1;
        input real ra1;
        input real rt2;
        input real ra2;
        input real rt3;
        input real ra3;
        input real rthreshold;
        real dt21;
        real dt32;
        real dt31;
        real ln1;
        real ln2;
        real ln3;
        real lnthr;
        real tau_est;
        real c2;
        real c1;
        begin
            dt21 = rt2 - rt1;
            dt32 = rt3 - rt2;
            dt31 = rt3 - rt1;
            ln1 = $ln(ra1);
            ln2 = $ln(ra2);
            ln3 = $ln(ra3);
            lnthr = $ln(rthreshold);

            case (mode)
                MODE_LINEAR:
                    expected_t0 = rt1 - ra1 * dt21 / (ra2 - ra1);
                MODE_EXP: begin
                    tau_est = dt32 / (ln3 - ln2);
                    expected_t0 = rt1 - tau_est * (ln1 - lnthr);
                end
                MODE_LOG: begin
                    c2 = ((ln3 - ln1) * dt21 - (ln2 - ln1) * dt31) /
                         (dt31 * dt21 * (dt31 - dt21));
                    c1 = ((ln2 - ln1) / dt21) - c2 * (rt1 + rt2);
                    expected_t0 = -c1 / (2.0 * c2);
                end
                default:
                    expected_t0 = 0.0;
            endcase
        end
    endfunction

    function real tolerance_ns;
        input integer mode;
        begin
            case (mode)
                MODE_LINEAR: tolerance_ns = 0.10;
                MODE_EXP:    tolerance_ns = 0.60;
                MODE_LOG:    tolerance_ns = 0.20;
                default:     tolerance_ns = 999.0;
            endcase
        end
    endfunction

    task run_case;
        input integer event_id;
        input integer mode;
        input real rt1;
        input real ra1;
        input real rt2;
        input real ra2;
        input real rt3;
        input real ra3;
        input real true_t0;
        input real rthreshold;
        integer start_cycle;
        integer valid_cycle;
        integer wait_cycles;
        integer pass;
        real expected_ns;
        real estimated_ns;
        real amax_ns;
        real error_expected_ns;
        real error_true_ns;
        real tol_ns;
        begin
            @(negedge clk);
            mode_sel  = mode[1:0];
            t1        = q16(rt1);
            a1        = q16(ra1);
            t2        = q16(rt2);
            a2        = q16(ra2);
            t3        = q16(rt3);
            a3        = q16(ra3);
            threshold = q16(rthreshold);
            start     = 1'b1;

            @(posedge clk);
            start_cycle = $time / 10;

            @(negedge clk);
            start = 1'b0;

            wait_cycles = 0;
            @(posedge clk);
            #1;
            while (!valid && wait_cycles < 100) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
            end
            valid_cycle = $time / 10;

            expected_ns = expected_t0(mode, rt1, ra1, rt2, ra2, rt3, ra3, rthreshold);
            estimated_ns = fq16(t0_est);
            amax_ns = fq16(amax_est);
            error_expected_ns = estimated_ns - expected_ns;
            error_true_ns = estimated_ns - true_t0;
            tol_ns = tolerance_ns(mode);
            pass = valid && !overflow && (abs_real(error_expected_ns) <= tol_ns);

            if (pass)
                pass_count = pass_count + 1;
            else
                fail_count = fail_count + 1;

            $fdisplay(csv_fd,
                "%0d,%0d,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0.9f,%0d,%0d,%0d,0x%08h,0x%08h,%0d",
                event_id, mode, rt1, ra1, rt2, ra2, rt3, ra3, rthreshold,
                true_t0, expected_ns, estimated_ns, amax_ns, error_expected_ns,
                error_true_ns, start_cycle, valid_cycle, valid_cycle - start_cycle,
                t0_est, amax_est, pass);
        end
    endtask

    task run_event_all_modes;
        input integer event_id;
        input real rt1;
        input real ra1;
        input real rt2;
        input real ra2;
        input real rt3;
        input real ra3;
        input real true_t0;
        input real rthreshold;
        begin
            run_case(event_id, MODE_LINEAR, rt1, ra1, rt2, ra2, rt3, ra3, true_t0, rthreshold);
            run_case(event_id, MODE_EXP,    rt1, ra1, rt2, ra2, rt3, ra3, true_t0, rthreshold);
            run_case(event_id, MODE_LOG,    rt1, ra1, rt2, ra2, rt3, ra3, true_t0, rthreshold);
        end
    endtask

    initial begin
        start = 1'b0;
        mode_sel = 2'd0;
        t1 = 32'sd0;
        a1 = 32'sd0;
        t2 = 32'sd0;
        a2 = 32'sd0;
        t3 = 32'sd0;
        a3 = 32'sd0;
        threshold = 32'sd0;
        pass_count = 0;
        fail_count = 0;
        event_count = 0;

        csv_fd = $fopen("leading_edge_core_results.csv", "w");
        if (csv_fd == 0) begin
            $display("ERROR: cannot open leading_edge_core_results.csv");
            $finish;
        end

        input_fd = $fopen("C:/Users/grzeg/Desktop/SDUP/leading_edge_python_model_v2/data/example_samples.csv", "r");
        if (input_fd == 0) begin
            $display("ERROR: cannot open input CSV");
            $finish;
        end

        scan_count = $fscanf(input_fd, "%s\n", header_line);

        $fdisplay(csv_fd,
            "event_id,method_id,t1,A1,t2,A2,t3,A3,threshold,true_t0,expected_t0,t0_est,amax_est,error_vs_expected_ns,error_vs_true_ns,start_cycle,valid_cycle,latency_cycles,t0_raw,amax_raw,pass");

        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        while (!$feof(input_fd)) begin
            scan_count = $fscanf(input_fd,
                "%d,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f\n",
                event_count,
                csv_t1,
                csv_a1,
                csv_t2,
                csv_a2,
                csv_t3,
                csv_a3,
                csv_true_t0,
                csv_true_amax,
                csv_sigma_ns,
                csv_tau_ns,
                csv_threshold,
                csv_charge,
                csv_true_t_leading,
                csv_true_t_trailing,
                csv_true_tot);

            if (scan_count == 16) begin
                run_event_all_modes(
                    event_count,
                    csv_t1,
                    csv_a1,
                    csv_t2,
                    csv_a2,
                    csv_t3,
                    csv_a3,
                    csv_true_t0,
                    csv_threshold);
                event_count = event_count + 1;
            end
        end

        repeat (10) @(posedge clk);
        $fclose(input_fd);
        $fclose(csv_fd);

        $display("leading_edge_core simulation complete: %0d events, %0d PASS, %0d FAIL", event_count, pass_count, fail_count);
        $finish;
    end

endmodule
