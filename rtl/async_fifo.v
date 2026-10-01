module axis_async_fifo_bridge #(
    parameter TDATA_WIDTH = 8,
    parameter ADDR_WIDTH  = 4 // FIFO Depth = 2^ADDR_WIDTH = 16
)(
    // AXI4-Stream Slave Interface (Write Clock Domain)
    input  wire                   s_axis_aclk,
    input  wire                   s_axis_aresetn,
    input  wire [TDATA_WIDTH-1:0] s_axis_tdata,
    input  wire                   s_axis_tvalid,
    input  wire                   s_axis_tlast,
    output wire                   s_axis_tready,

    // AXI4-Stream Master Interface (Read Clock Domain)
    input  wire                   m_axis_aclk,
    input  wire                   m_axis_aresetn,
    output wire [TDATA_WIDTH-1:0] m_axis_tdata,
    output wire                   m_axis_tvalid,
    output wire                   m_axis_tlast,
    input  wire                   m_axis_tready
);

    localparam FIFO_WIDTH = TDATA_WIDTH + 1;

    wire [FIFO_WIDTH-1:0] wdata_int;
    wire [FIFO_WIDTH-1:0] rdata_int;
    wire wfull_int;
    wire rempty_int;
    wire winc_int;
    wire rinc_int;

    // Slave Interface Logic (Write side)
    assign s_axis_tready = ~wfull_int;
    assign wdata_int     = {s_axis_tlast, s_axis_tdata};
    assign winc_int      = s_axis_tvalid & s_axis_tready;

    // Master Interface Logic (Read side)
    assign m_axis_tvalid = ~rempty_int;
    assign m_axis_tlast  = rdata_int[FIFO_WIDTH-1];
    assign m_axis_tdata  = rdata_int[TDATA_WIDTH-1:0];
    assign rinc_int      = m_axis_tvalid & m_axis_tready;

    // Core Asynchronous FIFO Instantiation
    async_fifo #(
        .DATA_WIDTH(FIFO_WIDTH), 
        .ADDR_WIDTH(ADDR_WIDTH)
    ) core_fifo_inst (
        .wclk   (s_axis_aclk),
        .wrst_n (s_axis_aresetn),
        .winc   (winc_int),
        .wdata  (wdata_int),
        .wfull  (wfull_int),
        .rclk   (m_axis_aclk),
        .rrst_n (m_axis_aresetn),
        .rinc   (rinc_int),
        .rdata  (rdata_int),
        .rempty (rempty_int)
    );
endmodule

module async_fifo #(
    parameter DATA_WIDTH = 9,
    parameter ADDR_WIDTH = 4
)(
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  winc,
    input  wire [DATA_WIDTH-1:0] wdata,
    output wire                  wfull,

    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  rinc,
    output wire [DATA_WIDTH-1:0] rdata,
    output wire                  rempty
);

    // Binary pointers
    // Used ONLY for memory addressing.
    wire [ADDR_WIDTH:0] wbin;
    wire [ADDR_WIDTH:0] rbin;

    // Gray-coded pointers
    // Used for CDC synchronization and full/empty detection.
    wire [ADDR_WIDTH:0] wptr;
    wire [ADDR_WIDTH:0] rptr;

    // Synchronized Gray pointers
    wire [ADDR_WIDTH:0] wq2_rptr;
    wire [ADDR_WIDTH:0] rq2_wptr;

    // ------------------------------------------------------------
    // Synchronize read pointer from read domain -> write domain
    // ------------------------------------------------------------

    sync_r2w #(ADDR_WIDTH) sync_r2w_inst (
        .wq2_rptr(wq2_rptr),
        .rptr    (rptr),
        .wclk    (wclk),
        .wrst_n  (wrst_n)
    );

    // ------------------------------------------------------------
    // Synchronize write pointer from write domain -> read domain
    // ------------------------------------------------------------

    sync_w2r #(ADDR_WIDTH) sync_w2r_inst (
        .rq2_wptr(rq2_wptr),
        .wptr    (wptr),
        .rclk    (rclk),
        .rrst_n  (rrst_n)
    );

    // ------------------------------------------------------------
    // FIFO memory
    //
    // IMPORTANT:
    // Use BINARY pointers for RAM addressing.
    // ------------------------------------------------------------

    fifomem #(DATA_WIDTH, ADDR_WIDTH) fifomem_inst (
        .rdata (rdata),
        .wdata (wdata),

        .waddr (wbin[ADDR_WIDTH-1:0]),
        .raddr (rbin[ADDR_WIDTH-1:0]),

        .wclken(winc & ~wfull),
        .wclk  (wclk)
    );

    // ------------------------------------------------------------
    // Read pointer / empty generation
    // ------------------------------------------------------------

    rptr_empty #(ADDR_WIDTH) rptr_empty_inst (
        .rempty  (rempty),
        .rptr    (rptr),
        .rbin    (rbin),
        .rq2_wptr(rq2_wptr),
        .rinc    (rinc),
        .rclk    (rclk),
        .rrst_n  (rrst_n)
    );

    // ------------------------------------------------------------
    // Write pointer / full generation
    // ------------------------------------------------------------

    wptr_full #(ADDR_WIDTH) wptr_full_inst (
        .wfull   (wfull),
        .wptr    (wptr),
        .wbin    (wbin),
        .wq2_rptr(wq2_rptr),
        .winc    (winc),
        .wclk    (wclk),
        .wrst_n  (wrst_n)
    );

endmodule
