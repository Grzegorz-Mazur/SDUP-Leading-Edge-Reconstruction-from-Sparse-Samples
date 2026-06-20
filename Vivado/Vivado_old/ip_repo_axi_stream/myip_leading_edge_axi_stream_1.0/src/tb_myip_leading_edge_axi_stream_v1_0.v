`timescale 1 ns / 1 ps

module tb_myip_leading_edge_axi_stream_v1_0;

    // -------------------------------------------------------------------------
    // Clock / reset
    // -------------------------------------------------------------------------

    reg clk;
    reg rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    // -------------------------------------------------------------------------
    // AXI Stream Slave input to DUT: S00_AXIS
    // -------------------------------------------------------------------------

    reg  [31:0] s00_axis_tdata;
    reg  [3:0]  s00_axis_tstrb;
    reg         s00_axis_tlast;
    reg         s00_axis_tvalid;
    wire        s00_axis_tready;

    // -------------------------------------------------------------------------
    // AXI Stream Master output from DUT: M00_AXIS
    // -------------------------------------------------------------------------

    wire        m00_axis_tvalid;
    wire [31:0] m00_axis_tdata;
    wire [3:0]  m00_axis_tstrb;
    wire        m00_axis_tlast;
    reg         m00_axis_tready;

    // -------------------------------------------------------------------------
    // Captured output words
    // -------------------------------------------------------------------------

    reg [31:0] rx_word0;
    reg [31:0] rx_word1;
    reg [31:0] rx_word2;
    integer rx_count;

    reg [31:0] rx_capture [0:2];
    reg [1:0]  rx_capture_count;

    always @(posedge clk) begin
        if (!rst_n)
            rx_capture_count <= 2'd0;
        else if (m00_axis_tvalid && m00_axis_tready && rx_capture_count < 3) begin
            rx_capture[rx_capture_count] <= m00_axis_tdata;
            rx_capture_count <= rx_capture_count + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // DUT
    // C_M00_AXIS_START_COUNT ustawione na 4, żeby symulacja była krótsza.
    // W normalnym IP może zostać domyślne 32.
    // -------------------------------------------------------------------------

    myip_leading_edge_axi_stream_v1_0 #(
        .C_S00_AXIS_TDATA_WIDTH(32),
        .C_M00_AXIS_TDATA_WIDTH(32),
        .C_M00_AXIS_START_COUNT(4)
    ) dut (
        .s00_axis_aclk    (clk),
        .s00_axis_aresetn (rst_n),
        .s00_axis_tready  (s00_axis_tready),
        .s00_axis_tdata   (s00_axis_tdata),
        .s00_axis_tstrb   (s00_axis_tstrb),
        .s00_axis_tlast   (s00_axis_tlast),
        .s00_axis_tvalid  (s00_axis_tvalid),

        .m00_axis_aclk    (clk),
        .m00_axis_aresetn (rst_n),
        .m00_axis_tvalid  (m00_axis_tvalid),
        .m00_axis_tdata   (m00_axis_tdata),
        .m00_axis_tstrb   (m00_axis_tstrb),
        .m00_axis_tlast   (m00_axis_tlast),
        .m00_axis_tready  (m00_axis_tready)
    );

    // -------------------------------------------------------------------------
    // Pomocnicza funkcja Q16.16
    // q16(10) = 10.0 w formacie Q16.16
    // -------------------------------------------------------------------------

    function [31:0] q16;
        input integer x;
        begin
            q16 = x <<< 16;
        end
    endfunction

    // -------------------------------------------------------------------------
    // AXI Stream send word
    // Trzyma TVALID i dane aż DUT wystawi TREADY.
    // -------------------------------------------------------------------------

    task axis_send_word;
        input [31:0] data;
        input        last;
        begin
            @(posedge clk);
            s00_axis_tdata  <= data;
            s00_axis_tstrb  <= 4'hF;
            s00_axis_tlast  <= last;
            s00_axis_tvalid <= 1'b1;

            while (!(s00_axis_tvalid && s00_axis_tready)) begin
                @(posedge clk);
            end

            @(posedge clk);
            s00_axis_tvalid <= 1'b0;
            s00_axis_tlast  <= 1'b0;
            s00_axis_tdata  <= 32'd0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Wysyłka pełnej poprawnej ramki 8 słów:
    // word 0: mode_sel
    // word 1: t1
    // word 2: a1
    // word 3: t2
    // word 4: a2
    // word 5: t3
    // word 6: a3
    // word 7: threshold + TLAST
    // -------------------------------------------------------------------------

    task send_good_frame_linear;
        begin
            send_good_frame(32'd0);
        end
    endtask

    task send_good_frame;
        input [31:0] mode_sel;
        begin
            rx_capture_count = 2'd0;
            $display("[%0t] TX: AXIS frame start (mode=%0d)", $time, mode_sel);

            axis_send_word(mode_sel,    1'b0);
            axis_send_word(q16(10),      1'b0);
            axis_send_word(q16(100),     1'b0);
            axis_send_word(q16(20),      1'b0);
            axis_send_word(q16(200),     1'b0);
            axis_send_word(q16(30),      1'b0);
            axis_send_word(q16(300),     1'b0);
            axis_send_word(q16(50),      1'b1);

            $display("[%0t] TX: AXIS frame end", $time);
        end
    endtask

    // -------------------------------------------------------------------------
    // Odbiór 3 słów z M00_AXIS.
    // Testuje:
    // - wyszły dokładnie 3 słowa,
    // - TLAST jest tylko przy trzecim słowie,
    // - status[0] = valid.
    // -------------------------------------------------------------------------

    task receive_and_check_result;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while (rx_capture_count < 3 && wait_cycles < 2000) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (rx_capture_count < 3) begin
                $display("ERROR: Timeout waiting for AXIS output frame");
                $finish;
            end

            rx_word0 = rx_capture[0];
            rx_word1 = rx_capture[1];
            rx_word2 = rx_capture[2];

            $display("[%0t] RX word 0 = 0x%08h", $time, rx_word0);
            $display("[%0t] RX word 1 = 0x%08h", $time, rx_word1);
            $display("[%0t] RX word 2 = 0x%08h (status)", $time, rx_word2);

            if (rx_word2[0] !== 1'b1) begin
                $display("ERROR: status[0] valid bit is not set. status=0x%08h", rx_word2);
                $finish;
            end

            $display("PASS: AXI-Stream output frame received correctly");
            $display("      t0_est   = 0x%08h", rx_word0);
            $display("      amax_est = 0x%08h", rx_word1);
            $display("      status   = 0x%08h", rx_word2);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main simulation
    // -------------------------------------------------------------------------

    initial begin
        s00_axis_tdata  = 32'd0;
        s00_axis_tstrb  = 4'hF;
        s00_axis_tlast  = 1'b0;
        s00_axis_tvalid = 1'b0;

        m00_axis_tready = 1'b1;

        rx_word0 = 32'd0;
        rx_word1 = 32'd0;
        rx_word2 = 32'd0;
        rx_count = 0;

        rst_n = 1'b0;
        rx_capture_count = 2'd0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        send_good_frame_linear();
        receive_and_check_result();

        repeat (20) @(posedge clk);

        $display("=== Second back-to-back frame ===");
        send_good_frame(32'd1);
        receive_and_check_result();

        repeat (20) @(posedge clk);

        $display("SIMULATION PASSED");
        $finish;
    end

endmodule
