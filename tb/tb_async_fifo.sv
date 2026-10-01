module tb_axis_async_fifo;

    parameter TDATA_WIDTH = 8;
    parameter ADDR_WIDTH  = 4;

    // ============================================================
    // DUT SIGNALS
    // ============================================================

    logic s_axis_aclk;
    logic s_axis_aresetn;
    logic m_axis_aclk;
    logic m_axis_aresetn;

    logic [TDATA_WIDTH-1:0] s_axis_tdata;
    logic                   s_axis_tvalid;
    logic                   s_axis_tlast;
    logic                   s_axis_tready;

    logic [TDATA_WIDTH-1:0] m_axis_tdata;
    logic                   m_axis_tvalid;
    logic                   m_axis_tlast;
    logic                   m_axis_tready;

    // ============================================================
    // DUT
    // ============================================================

    axis_async_fifo_bridge #(
        .TDATA_WIDTH(TDATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .s_axis_aclk    (s_axis_aclk),
        .s_axis_aresetn (s_axis_aresetn),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tlast   (s_axis_tlast),
        .s_axis_tready  (s_axis_tready),

        .m_axis_aclk    (m_axis_aclk),
        .m_axis_aresetn (m_axis_aresetn),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tlast   (m_axis_tlast),
        .m_axis_tready  (m_axis_tready)
    );

    // ============================================================
    // TRANSACTION TYPE
    // ============================================================

    typedef struct packed {
        logic                   tlast;
        logic [TDATA_WIDTH-1:0] tdata;
    } axis_beat_t;

    // Pre-generated stream of all expected beats.
    axis_beat_t expected_beats[$];

    // ============================================================
    // TEST CONFIGURATION / COUNTERS
    // ============================================================

    int total_pkts_to_send = 50;

    int expected_total_beats = 0;
    int beats_sent            = 0;
    int beats_received        = 0;
    int errors                = 0;

    bit source_done = 0;
    bit sink_done   = 0;

    // ============================================================
    // CLOCK GENERATION
    // ============================================================

    // Write clock = 100 MHz
    initial begin
        s_axis_aclk = 1'b0;
        forever #5 s_axis_aclk = ~s_axis_aclk;
    end

    // Read clock ~= 38.46 MHz
    initial begin
        m_axis_aclk = 1'b0;
        forever #13 m_axis_aclk = ~m_axis_aclk;
    end

    // ============================================================
    // PRE-GENERATE ALL TRAFFIC
    // ============================================================

    initial begin
        axis_beat_t beat;

        for (int pkt = 0; pkt < total_pkts_to_send; pkt++) begin

            int pkt_len;
            pkt_len = $urandom_range(4, 12);

            expected_total_beats += pkt_len;

            for (int beat_idx = 0; beat_idx < pkt_len; beat_idx++) begin

                beat.tdata = $urandom();
                beat.tlast = (beat_idx == pkt_len - 1);

                expected_beats.push_back(beat);
            end
        end

        $display("--------------------------------------------------");
        $display("Generated test traffic:");
        $display("  Packets      : %0d", total_pkts_to_send);
        $display("  Total beats  : %0d", expected_total_beats);
        $display("--------------------------------------------------");
    end

    // ============================================================
    // RESET
    // ============================================================

    initial begin
        s_axis_aresetn = 1'b0;
        m_axis_aresetn = 1'b0;

        s_axis_tvalid  = 1'b0;
        s_axis_tdata   = '0;
        s_axis_tlast   = 1'b0;

        m_axis_tready  = 1'b0;

        #50;

        s_axis_aresetn = 1'b1;
        m_axis_aresetn = 1'b1;

        // Allow both domains to settle after reset.
        #20;

        fork
            source_driver();
            sink_driver();
        join

        // ========================================================
        // FINAL RESULT
        // ========================================================

        $display("--------------------------------------------------");
        $display("TEST COMPLETE");
        $display("  Packets       : %0d", total_pkts_to_send);
        $display("  Expected beats: %0d", expected_total_beats);
        $display("  Sent beats    : %0d", beats_sent);
        $display("  Received beats: %0d", beats_received);
        $display("  Errors        : %0d", errors);
        $display("--------------------------------------------------");

        if (errors == 0 &&
            beats_sent == expected_total_beats &&
            beats_received == expected_total_beats) begin

            $display("TEST PASSED");
        end
        else begin
            $display("TEST FAILED");
            $fatal(1);
        end

        $finish;
    end

    // ============================================================
    // SOURCE DRIVER
    // ============================================================

    task automatic source_driver();

        axis_beat_t current_beat;

        for (int i = 0; i < expected_beats.size(); i++) begin

            current_beat = expected_beats[i];

            // ----------------------------------------------------
            // Random idle period between transfers
            // ----------------------------------------------------

            if ($urandom_range(0, 100) < 30) begin

                s_axis_tvalid <= 1'b0;

                repeat ($urandom_range(1, 4))
                    @(negedge s_axis_aclk);
            end

            // ----------------------------------------------------
            // Present beat
            // ----------------------------------------------------

            @(negedge s_axis_aclk);

            s_axis_tdata  <= current_beat.tdata;
            s_axis_tlast  <= current_beat.tlast;
            s_axis_tvalid <= 1'b1;

            // ----------------------------------------------------
            // Hold VALID/DATA/LAST until handshake
            // ----------------------------------------------------

            forever begin

                @(posedge s_axis_aclk);

                if (s_axis_tready) begin

                    // Actual AXI4-Stream handshake occurred.
                    beats_sent++;

                    break;
                end
            end
        end

        // Deassert VALID after final transfer.
        @(negedge s_axis_aclk);

        s_axis_tvalid <= 1'b0;
        s_axis_tdata  <= '0;
        s_axis_tlast  <= 1'b0;

        source_done = 1'b1;

        $display("Time %0t: SOURCE DONE - %0d beats sent",
                 $time, beats_sent);

    endtask

    // ============================================================
    // SINK DRIVER / MONITOR
    // ============================================================

    task automatic sink_driver();

        axis_beat_t expected_beat;

        while (1) begin

            // ----------------------------------------------------
            // Random backpressure.
            // Drive TREADY before the active sampling edge.
            // ----------------------------------------------------

            @(negedge m_axis_aclk);

            m_axis_tready <=
                ($urandom_range(0, 100) > 20) ? 1'b1 : 1'b0;

            // ----------------------------------------------------
            // Sample AXI transaction at rising edge.
            // No #1 delay here.
            // ----------------------------------------------------

            @(posedge m_axis_aclk);

            if (m_axis_tvalid && m_axis_tready) begin

                // ------------------------------------------------
                // Check that DUT never produced more data than
                // the source has actually accepted.
                // ------------------------------------------------

                if (beats_received >= beats_sent) begin

                    $error("Time %0t: FIFO produced data that was never written!",
                           $time);

                    errors++;
                end

                // ------------------------------------------------
                // Check expected sequence.
                // ------------------------------------------------

                if (beats_received >= expected_beats.size()) begin

                    $error("Time %0t: Received more beats than expected!",
                           $time);

                    errors++;
                end
                else begin

                    expected_beat = expected_beats[beats_received];

                    if (m_axis_tdata !== expected_beat.tdata ||
                        m_axis_tlast !== expected_beat.tlast) begin

                        $error(
                            "Time %0t: DATA MISMATCH at beat %0d | " +
                            "Expected: DATA=%h TLAST=%b | " +
                            "Got: DATA=%h TLAST=%b",
                            $time,
                            beats_received,
                            expected_beat.tdata,
                            expected_beat.tlast,
                            m_axis_tdata,
                            m_axis_tlast
                        );

                        errors++;
                    end

                    beats_received++;
                end
            end

            // ----------------------------------------------------
            // Completion condition.
            // ----------------------------------------------------

            if (source_done &&
                beats_received == expected_total_beats) begin

                break;
            end
        end

        m_axis_tready <= 1'b0;

        sink_done = 1'b1;

        $display("Time %0t: SINK DONE - %0d beats received",
                 $time, beats_received);

    endtask

    // ============================================================
    // AXI4-STREAM ASSERTIONS
    // ============================================================

    // ------------------------------------------------------------
    // VALID must remain asserted while stalled.
    // ------------------------------------------------------------

    property p_tvalid_stable;
        @(posedge s_axis_aclk)
        disable iff (!s_axis_aresetn)
        (s_axis_tvalid && !s_axis_tready)
        |=> s_axis_tvalid;
    endproperty

    assert_tvalid_stable:
        assert property (p_tvalid_stable)
        else begin
            $error("SVA VIOLATION: TVALID dropped while TREADY was low.");
            errors++;
        end

    // ------------------------------------------------------------
    // DATA and TLAST must remain stable while stalled.
    // ------------------------------------------------------------

    property p_tdata_stable;
        @(posedge s_axis_aclk)
        disable iff (!s_axis_aresetn)
        (s_axis_tvalid && !s_axis_tready)
        |=> ($stable(s_axis_tdata) &&
             $stable(s_axis_tlast));
    endproperty

    assert_tdata_stable:
        assert property (p_tdata_stable)
        else begin
            $error(
                "SVA VIOLATION: TDATA/TLAST changed while TVALID=1 and TREADY=0."
            );
            errors++;
        end

    // ------------------------------------------------------------
    // No X/Z on source control signals.
    // ------------------------------------------------------------

    property p_no_x_z_control;
        @(posedge s_axis_aclk)
        disable iff (!s_axis_aresetn)
        (!$isunknown(s_axis_tvalid) &&
         !$isunknown(s_axis_tready));
    endproperty

    assert_no_x_z_control:
        assert property (p_no_x_z_control)
        else begin
            $error("SVA VIOLATION: TVALID/TREADY contains X or Z.");
            errors++;
        end

    // ------------------------------------------------------------
    // Master side: VALID/data must remain stable while stalled.
    // ------------------------------------------------------------

    property p_m_axis_stable;
        @(posedge m_axis_aclk)
        disable iff (!m_axis_aresetn)
        (m_axis_tvalid && !m_axis_tready)
        |=> (m_axis_tvalid &&
             $stable(m_axis_tdata) &&
             $stable(m_axis_tlast));
    endproperty

    assert_m_axis_stable:
        assert property (p_m_axis_stable)
        else begin
            $error(
                "SVA VIOLATION: M_AXIS data/TLAST changed while stalled."
            );
            errors++;
        end

    // ------------------------------------------------------------
    // No X/Z on output controls.
    // ------------------------------------------------------------

    property p_m_axis_no_x;
        @(posedge m_axis_aclk)
        disable iff (!m_axis_aresetn)
        (!$isunknown(m_axis_tvalid) &&
         !$isunknown(m_axis_tready));
    endproperty

    assert_m_axis_no_x:
        assert property (p_m_axis_no_x)
        else begin
            $error("SVA VIOLATION: M_AXIS TVALID/TREADY contains X or Z.");
            errors++;
        end

    // ============================================================
    // WATCHDOG TIMER (TIMEOUT)
    // ============================================================

    initial begin
        // Adjust the time limit safely above the expected execution time
        #500000;
        $display("Time %0t: FATAL ERROR - Simulation timeout reached. Possible deadlock.", $time);
        $fatal(1);
    end

endmodule
