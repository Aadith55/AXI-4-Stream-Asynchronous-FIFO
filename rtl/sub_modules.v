module fifomem #(parameter DATASIZE = 9, parameter ADDRSIZE = 4)(
    output wire [DATASIZE-1:0] rdata,
    input  wire [DATASIZE-1:0] wdata,
    input  wire [ADDRSIZE-1:0] waddr, raddr,
    input  wire                wclken, wclk
);
    localparam DEPTH = 1 << ADDRSIZE;
    reg [DATASIZE-1:0] mem [0:DEPTH-1];
    assign rdata = mem[raddr];
    always @(posedge wclk) begin
        if (wclken) mem[waddr] <= wdata;
    end
endmodule

module sync_r2w #(parameter ADDRSIZE = 4)(
    output reg  [ADDRSIZE:0] wq2_rptr,
    input  wire [ADDRSIZE:0] rptr,
    input  wire              wclk, wrst_n
);
    reg [ADDRSIZE:0] wq1_rptr;
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) {wq2_rptr, wq1_rptr} <= 0;
        else         {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr};
    end
endmodule

module sync_w2r #(parameter ADDRSIZE = 4)(
    output reg  [ADDRSIZE:0] rq2_wptr,
    input  wire [ADDRSIZE:0] wptr,
    input  wire              rclk, rrst_n
);
    reg [ADDRSIZE:0] rq1_wptr;
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) {rq2_wptr, rq1_wptr} <= 0;
        else         {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr};
    end
endmodule

module rptr_empty #(parameter ADDRSIZE = 4)(
    output reg               rempty,
    output reg  [ADDRSIZE:0] rptr,
    output reg  [ADDRSIZE:0] rbin,

    input  wire [ADDRSIZE:0] rq2_wptr,
    input  wire              rinc,
    input  wire              rclk,
    input  wire              rrst_n
);

    wire [ADDRSIZE:0] rgraynext;
    wire [ADDRSIZE:0] rbinnext;
    wire              rempty_val;

    // ------------------------------------------------------------
    // Binary read pointer
    // ------------------------------------------------------------

    assign rbinnext = rbin + (rinc & ~rempty);

    // Binary -> Gray
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;

    // ------------------------------------------------------------
    // Update binary and Gray read pointers
    // ------------------------------------------------------------

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin <= 0;
            rptr <= 0;
        end
        else begin
            rbin <= rbinnext;
            rptr <= rgraynext;
        end
    end

    // ------------------------------------------------------------
    // FIFO empty detection
    // ------------------------------------------------------------

    assign rempty_val = (rgraynext == rq2_wptr);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)
            rempty <= 1'b1;
        else
            rempty <= rempty_val;
    end

endmodule

module wptr_full #(parameter ADDRSIZE = 4)(
    output reg               wfull,
    output reg  [ADDRSIZE:0] wptr,
    output reg  [ADDRSIZE:0] wbin,

    input  wire [ADDRSIZE:0] wq2_rptr,
    input  wire              winc,
    input  wire              wclk,
    input  wire              wrst_n
);

    wire [ADDRSIZE:0] wgraynext;
    wire [ADDRSIZE:0] wbinnext;
    wire              wfull_val;

    // ------------------------------------------------------------
    // Binary write pointer
    // ------------------------------------------------------------

    assign wbinnext = wbin + (winc & ~wfull);

    // Binary -> Gray
    assign wgraynext = (wbinnext >> 1) ^ wbinnext;

    // ------------------------------------------------------------
    // Update binary and Gray write pointers
    // ------------------------------------------------------------

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin <= 0;
            wptr <= 0;
        end
        else begin
            wbin <= wbinnext;
            wptr <= wgraynext;
        end
    end

    // ------------------------------------------------------------
    // FIFO full detection
    // ------------------------------------------------------------

    assign wfull_val =
        (wgraynext ==
        {
            ~wq2_rptr[ADDRSIZE:ADDRSIZE-1],
             wq2_rptr[ADDRSIZE-2:0]
        });

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n)
            wfull <= 1'b0;
        else
            wfull <= wfull_val;
    end

endmodule
